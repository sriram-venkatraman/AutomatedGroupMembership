public with sharing class AutomatedGroupMemberHandler {
    public AutomatedGroupMemberHandler() {

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
        List<Automated_Group_Membership_Config__mdt> config = [select MasterLabel, 
                                                                        Where_Clause__c, 
                                                                        Group_Names__c,
                                                                        Notification_Frequency__c,
                                                                        Role__c,
                                                                        Remove_User_If_Not_Meeting_Criteria__c
                                                                from   Automated_Group_Membership_Config__mdt 
                                                                where  IsActive__c = true
                                                                limit 50];

        Set<String> groupList = new Set<String>();
        List<String> tmpList;
        List<ConfigDef> configDefList = new List<ConfigDef>();
        for (Automated_Group_Membership_Config__mdt c : config) {
            tmpList = c.Group_Names__c.split(',');
            
            ConfigDef cd = new ConfigDef();
            cd.configLabel = c.MasterLabel;
            cd.whereClause = c.Where_Clause__c;
            switch on c.Notification_Frequency__c {
                when 'Every Post' {
                    cd.notificationFrequency = 'P';
                }
                when 'Daily' {
                    cd.notificationFrequency = 'D';
                }
                when 'Weekly' {
                    cd.notificationFrequency = 'W';
                }
                when else {
                    cd.notificationFrequency = 'N';
                }
            }
            groupList.addAll(tmpList);
            
            cd.role = (c.Role__c == 'Member' ? 'Standard' : 'Admin');

            cd.groupIdMap = new Map<String, String>();
            for (String s : tmpList) {
                cd.groupIdMap.put(s, '');
            }
            cd.userIdList = new List<User>();
            configDefList.add(cd);
        }
        system.debug(configDefList);

        Map<String, String> groupMap = new Map<String, String>();
        for (CollaborationGroup cg : [select id, name from collaborationgroup where isarchived = false and name = :groupList]) {
            groupMap.put(cg.name, cg.id);
        }

        Set<Id> fullUserIdList = new Set<Id>();
        String userQuery = 'select Id from User where IsActive = true';

        for (Integer i = 0; i < configDefList.size(); i++) {
            for (String k : configDefList[i].groupIdMap.keySet()) {
                configDefList[i].groupIdMap.put(k, groupMap.get(k));
            } 
            configDefList[i].userIdList = Database.query(userQuery + ' ' + configDefList[i].whereClause);
            for (User u : configDefList[i].userIdList) {
                fullUserIdList.add(u.Id);
            }
        }

        Map<String, String> existingcgmMap = new Map<String, String>();
        
        for (CollaborationGroupMember cgm : [select Id, CollaborationGroupId, MemberId, CollaborationGroup.OwnerId from CollaborationGroupMember where CollaborationGroup.name = :groupList]) {
            existingcgmMap.put(cgm.CollaborationGroupId + '-' + cgm.MemberId, (cgm.MemberId == cgm.CollaborationGroup.OwnerId ? 'o:' : '') + cgm.Id);
        }
        system.debug('Existing: ' + existingcgmMap.size());

        List<CollaborationGroupMember> newcgmList = new List<CollaborationGroupMember>();
        Set<String> fullcgmKeys = new Set<String>();
        List<CollaborationGroupMember> deletecgmList = new List<CollaborationGroupMember>();

        Set<String> newcgmKeys = new Set<String>();
        CollaborationGroupMember cgm;
        for (ConfigDef cd : configDefList) {
            for (String g : cd.groupIdMap.values()) {
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
        insert newcgmList;

        for (String cgmKey : existingcgmMap.keySet()) {
            if (!fullcgmKeys.contains(cgmKey)) {
                if (!existingcgmMap.get(cgmKey).startsWith('o:')) {
                    deletecgmList.add(new CollaborationGroupMember(Id = existingcgmMap.get(cgmKey))); 
                }
            }
        }

        system.debug('Deletes: ' + deletecgmList.size());
        delete deletecgmList;
    }
}