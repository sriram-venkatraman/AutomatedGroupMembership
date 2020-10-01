public with sharing class AutomatedGroupMemberHandler {
    private static Integer MAX_CONFIG_GROUPS_ALLOWED = 50;
    private Set<String> listOfUserIds = new Set<String>();

    public AutomatedGroupMemberHandler() {
    }

    public AutomatedGroupMemberHandler(List<String> listUIds) {
        this.listOfUserIds.addAll(listUIds);
    }

    public AutomatedGroupMemberHandler(Set<String> listUIds) {
        this.listOfUserIds.addAll(listUIds);
    }

    class ConfigDef {
        String configLabel;
        String whereClause;
        Map<String, String> groupIdMap;
        List<User> userIdList;
        String notificationFrequency;
        String role;
        Boolean removeUsers;
    }

    public void addMembers() {
        List<Automated_Group_Membership_Config__mdt> config;
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

        if (config.size() == 0) {
            System.Debug('No Configuration found');
            return;
        }
        if (config.size() > MAX_CONFIG_GROUPS_ALLOWED) {
            throw new AutomatedGroupMemberHandler.HandlerException('Error! Process can not handle more than ' + MAX_CONFIG_GROUPS_ALLOWED + ' Active Configuration Definitions.');
        }

        Set<String> groupList = new Set<String>();
        List<String> tmpList;
        List<ConfigDef> configDefList = new List<ConfigDef>();
        for (Automated_Group_Membership_Config__mdt c : config) {
            tmpList = c.Group_Names__c.split(',');
            groupList.addAll(tmpList);
            
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

            cd.groupIdMap = new Map<String, String>();
            for (String s : tmpList) {
                cd.groupIdMap.put(s, '');
            }
            cd.userIdList = new List<User>();
            configDefList.add(cd);
        }
        system.debug(configDefList);

        Map<String, String> groupMap = new Map<String, String>();
        try {
            for (CollaborationGroup cg : [select id, name from collaborationgroup where isarchived = false and name = :groupList]) {
                groupMap.put(cg.name, cg.id);
            }
        } catch(Exception ex) {
            throw new AutomatedGroupMemberHandler.HandlerException(ex.getMessage() + '\nStack Trace: ' + ex.getStackTraceString());
        }         

        Set<Id> fullUserIdList = new Set<Id>();
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
            for (User u : configDefList[i].userIdList) {
                fullUserIdList.add(u.Id);
            }
        }
        System.debug('Full User List: ' + fullUserIdList);

        Map<String, String> existingcgmMap = new Map<String, String>();
        
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
        system.debug('Existing CGM List: ' + existingcgmMap);
        system.debug('Existing: ' + existingcgmMap.size());

        List<CollaborationGroupMember> newcgmList = new List<CollaborationGroupMember>();
        Set<String> fullcgmKeys = new Set<String>();

        // Used if group membership needs to be removed for users no longer matching criteria
        List<CollaborationGroupMember> deletecgmList = new List<CollaborationGroupMember>();

        CollaborationGroupMember cgm;
        Set<String> groupsQualifyForUserRemoval = new Set<String>();
        for (ConfigDef cd : configDefList) {
            for (String g : cd.groupIdMap.values()) {
                if (cd.removeUsers) {
                    groupsQualifyForUserRemoval.add(g);
                }
                for (User u : cd.userIdList) {
                    cgm = new CollaborationGroupMember();
                    cgm.CollaborationGroupId = g;
                    cgm.MemberId = u.Id;
                    cgm.CollaborationRole = cd.role;
                    cgm.NotificationFrequency = cd.notificationFrequency;
                    fullcgmKeys.add(g + '-' + u.Id);
                    if (!existingcgmMap.containsKey(g + '-' + u.Id)) {
                        newcgmList.add(cgm);
                    }
                }
            }
        }

        system.debug('Full: ' + fullcgmKeys.size());
        system.debug('Adds: ' + newcgmList.size());
        if (newcgmList.size() > 0) {
            insert newcgmList;
        }

        for (String cgmKey : existingcgmMap.keySet()) {
            if (groupsQualifyForUserRemoval.contains(cgmKey.split('-')[0]) && this.listOfUserIds.contains(cgmKey.split('-')[1])) {
                if (!fullcgmKeys.contains(cgmKey)) {
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