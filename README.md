[![Deploy to Salesforce](https://andrewfawcett.files.wordpress.com/2014/09/deploy.png)](https://githubsfdeploy.herokuapp.com/app/githubdeploy/sriram-venkatraman/AutomatedGroupMembership)

# Salesforce App

## Dev, Build and Test
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


## Resources

## Description of Files and Directories

## Issues
# AutomatedGroupMembership
