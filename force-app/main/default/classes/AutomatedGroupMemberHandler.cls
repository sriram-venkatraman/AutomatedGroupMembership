public with sharing class AutomatedGroupMemberHandler {
    private static Integer MAX_CONFIG_GROUPS_ALLOWED = 50;
    private Set<String> listOfUserIds = new Set<String>();

    public AutomatedGroupMemberHandler() {
    }

    // Use this constructor to call from User trigger (typically) passing it a list of UserIds to manage
    public AutomatedGroupMemberHandler(List<String> listUIds) {
        this.listOfUserIds.addAll(listUIds);
    }

    public AutomatedGroupMemberHandler(Set<String> listUIds) {
        this.listOfUserIds.addAll(listUIds);
    }

    // Structure to hold configuration definition from the metadata type
    class ConfigDef {
        String configLabel;
        String whereClause;
        Map<String, String> groupIdMap;
        List<User> userIdList;
        String notificationFrequency;
        String role;
        Boolean removeUsers;
    }

    // Core method that basically compares group memberships as it exists vs should exist based on criteria
    // from the config defs. Adds are processed if they don't exist; Deletes are processed only if they exist
    // and we explicitly want the group membership to be removed via config.
    public void addDeleteMembers() {
        List<Automated_Group_Membership_Config__mdt> config;

        // Get the config Definitions.. Can't handle more than MAX CONFIG limit at this point due to concerns
        // around SOQL 101 error
        try {
            config = [select MasterLabel, 
                             Where_Clause__c, 
                             Group_Names__c,
                             Notification_Frequency__c,
                             Role__c,
                             Remove_User_If_Not_Meeting_Criteria__c
                     from    Automated_Group_Membership_Config__mdt 
                     where   IsActive__c = true
                    ];
        } catch(Exception ex) {
            throw new AutomatedGroupMemberHandler.HandlerException(ex.getMessage() + '\nStack Trace: ' + ex.getStackTraceString());
        } 

        // No config found, so do nothing
        if (config.size() == 0) {
            System.Debug('No Configuration found');
            return;
        }

        // Error out if more than max configs
        if (config.size() > MAX_CONFIG_GROUPS_ALLOWED) {
            throw new AutomatedGroupMemberHandler.HandlerException('Error! Process can not handle more than ' + MAX_CONFIG_GROUPS_ALLOWED + ' Active Configuration Definitions.');
        }

        Set<String> groupList = new Set<String>();
        List<String> tmpList;
        List<ConfigDef> configDefList = new List<ConfigDef>();

        // Process thru' config def list
        for (Automated_Group_Membership_Config__mdt c : config) {
            ConfigDef cd = new ConfigDef();
            cd.configLabel = c.MasterLabel;
            cd.whereClause = c.Where_Clause__c;

            cd.notificationFrequency = 'N';
            if (c.Notification_Frequency__c == 'Every Post') {
                cd.notificationFrequency = 'P';
            }
            if (c.Notification_Frequency__c == 'Daily') {
                cd.notificationFrequency = 'D';
            }
            if (c.Notification_Frequency__c == 'Weekly') {
                cd.notificationFrequency = 'W';
            }
            cd.role = (c.Role__c == 'Member' ? 'Standard' : 'Admin');
            cd.removeUsers = c.Remove_User_If_Not_Meeting_Criteria__c;

            tmpList = c.Group_Names__c.split(',');
            // Collect all group names across all configs; This required to query group object to get the Ids
            groupList.addAll(tmpList);            
            cd.groupIdMap = new Map<String, String>();
            // For each config, we will get the group name and id in a map; This is required for adding new
            // membership records later
            for (String s : tmpList) {
                cd.groupIdMap.put(s, '');
            }
            cd.userIdList = new List<User>();
            configDefList.add(cd);
        }
        system.debug(configDefList);

        // Get all the group name and id for all groups in groupList and put the name & the id in the groupMap
        Map<String, String> groupMap = new Map<String, String>();
        try {
            for (CollaborationGroup cg : [select id, name from collaborationgroup where isarchived = false and name = :groupList]) {
                groupMap.put(cg.name, cg.id);
            }
        } catch(Exception ex) {
            throw new AutomatedGroupMemberHandler.HandlerException(ex.getMessage() + '\nStack Trace: ' + ex.getStackTraceString());
        } 

        String userQuery = 'select Id from User where IsActive = true';

        // Process thru config def
        for (Integer i = 0; i < configDefList.size(); i++) {
            // Collect group name + Id in the map for each config Definition
            for (String k : configDefList[i].groupIdMap.keySet()) {
                configDefList[i].groupIdMap.put(k, groupMap.get(k));
            } 

            // For each config def, run the user criteria query. WARNING this is where you can get 
            // SOQL 101 if we didn't limit the number of Config Def. 
            // Future enhancement: May have to break the process into chunks of 50 def records and 
            // run them via flex queues.
            try {
                configDefList[i].userIdList = Database.query(userQuery + ' ' + 
                                                             (this.listOfUserIds.size() > 0 ? ' and Id = :listOfUserIds ' : '' ) + 
                                                             configDefList[i].whereClause );
            } catch(Exception ex) {
                throw new AutomatedGroupMemberHandler.HandlerException(ex.getMessage() + '\nStack Trace: ' + ex.getStackTraceString());
            } 
        }

        Map<String, String> existingcgmMap = new Map<String, String>();
        
        // Collect existing Group Membership records; Put a 'o:' to ensure the cgm record is actually for the Group Owner
        if (this.listOfUserIds.size() <= 0) {
            for (CollaborationGroupMember cgm : [select Id, CollaborationGroupId, MemberId, CollaborationGroup.OwnerId from CollaborationGroupMember where CollaborationGroup.name = :groupList]) {
                existingcgmMap.put(cgm.CollaborationGroupId + '-' + cgm.MemberId, (cgm.MemberId == cgm.CollaborationGroup.OwnerId ? 'o:' : '') + cgm.Id);
            }
        }
        else {
            for (CollaborationGroupMember cgm : [select Id, CollaborationGroupId, MemberId, CollaborationGroup.OwnerId from CollaborationGroupMember where CollaborationGroup.name = :groupList and MemberId = :listOfUserIds]) {
                existingcgmMap.put(cgm.CollaborationGroupId + '-' + cgm.MemberId, (cgm.MemberId == cgm.CollaborationGroup.OwnerId ? 'o:' : '') + cgm.Id);
            }
        }
        System.debug('Existing: ' + existingcgmMap.size());

        List<CollaborationGroupMember> newcgmList = new List<CollaborationGroupMember>();
        Set<String> tobestatecgmKeys = new Set<String>();

        // Used if group membership needs to be removed for users no longer matching criteria
        List<CollaborationGroupMember> deletecgmList = new List<CollaborationGroupMember>();

        CollaborationGroupMember cgm;
        Set<String> groupsQualifyForUserRemoval = new Set<String>();
        for (ConfigDef cd : configDefList) {
            for (String g : cd.groupIdMap.values()) {
                // If a group was identified for user removal, save it in this list
                if (cd.removeUsers) {
                    groupsQualifyForUserRemoval.add(g);
                }
                // Form the to be state & the pure adds to group member object
                for (User u : cd.userIdList) {
                    cgm = new CollaborationGroupMember();
                    cgm.CollaborationGroupId = g;
                    cgm.MemberId = u.Id;
                    cgm.CollaborationRole = cd.role;
                    cgm.NotificationFrequency = cd.notificationFrequency;
                    // to be state key list (groupid+userid)
                    tobestatecgmKeys.add(g + '-' + u.Id);

                    // add to the new list only if the membership doesn't exist
                    if (!existingcgmMap.containsKey(g + '-' + u.Id)) {
                        newcgmList.add(cgm);
                    }
                }
            }
        }

        system.debug('Full: ' + tobestatecgmKeys.size());
        system.debug('Adds: ' + newcgmList.size());
        if (newcgmList.size() > 0) {
            insert newcgmList;
        }

        // Parse thru' existing membership; for every group+memberid combo, see if it should exists based
        // on the tobestatekey list; 
        for (String cgmKey : existingcgmMap.keySet()) {
            // Do deletes only if the Group was identified in on of the config for user removals 
            // Also limit the user removal only to the list of users that might have been passed to this class via
            // contstructor
            if (groupsQualifyForUserRemoval.contains(cgmKey.split('-')[0]) && this.listOfUserIds.contains(cgmKey.split('-')[1])) {
                if (!tobestatecgmKeys.contains(cgmKey)) {
                    // You can't delete a owner of the group. So ensure the member record to be removed is not 
                    // the owner member record before deleting
                    if (!existingcgmMap.get(cgmKey).startsWith('o:')) {
                        deletecgmList.add(new CollaborationGroupMember(Id = existingcgmMap.get(cgmKey))); 
                    }
                }
            }
        }

        system.debug('Deletes: ' + deletecgmList.size());
        if (deletecgmList.size() > 0 ) {
            delete deletecgmList;
        }

        return;
    }

    public class HandlerException extends Exception { }
}