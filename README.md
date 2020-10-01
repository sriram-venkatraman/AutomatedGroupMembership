[![Deploy to Salesforce](https://andrewfawcett.files.wordpress.com/2014/09/deploy.png)](https://githubsfdeploy.herokuapp.com/app/githubdeploy/sriram-venkatraman/AutomatedGroupMembership)

# HTTP Callout Framework
*Note: Still tidying up with test classes and documentation. Functionality seems to work reasonably well although I haven't done extensive test*

The core class __AutomatedGroupMemberHandler__ helps add and delete Collaboration Group members automatically based on configuration defined in custom metadata.
* Ability to specify WHERE clause to determine which active user ids will be impacted by each configuration definition
* Ability to provide multiple Collaboration Groups in each configuration
* Ability to specify if a Collaboration Group membership needs to be deleted if non-owner members don't fit the criteria (WhereClause) mentioned in the configuration def. 
* Ability to specify Member roles and Notification frequencies via config

## Sample Callout
```
AutomatedGroupMemberHandler agmh = new AutomatedGroupMemberHandler();
agmh.addDeleteMembers();
```
OR

```
Set<String> s = new Set<String>();
s.add('<id>');
AutomatedGroupMemberHandler agmh = new AutomatedGroupMemberHandler(s);
agmh.addDeleteMembers();
```

## Important
* This Class can only handle 50 configuration at this time (may be slightly more) to ensure we don't hit SQL 101 error. Future enhancement can be expected to run batch processes via flex queue to support large volume configuration. 
* If a Collaboration Group was marked for User Removal in one configuration definition that setting will be carried for all other configurations.. 
** So if you want to manage both adds and deletes for a specific Collaboration Group, isolate them in separate config definitions

## Dev, Build and Test

## Resources

## Description of Files and Directories

## Issues
