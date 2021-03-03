# GetRankedPostsRequestParams

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**sort** | **str** | ### Sort order: trending - [if tag is community pinned posts first], top posts with highest trending score first; paging cuts out given and more trending posts hot - top posts from blogs of accounts that given account is following ranked by creation/reblog time, not older than last month   created - [if tag is community pinned posts first], newest top posts first (grayed out not considered); paging cuts out given and newer posts promoted - promoted posts with highest promotion fund first; paging cuts out given and more promoted posts payout - only posts that will cashout between 12 and 36 hours from head block are considered, posts with higher pending payout first; paging cuts out given and higher payout posts payout_comments - only replies are considered, posts with higher pending payout first; paging cuts out given and higher payout posts muted - grayed out posts that are to receive nonzero payout are considered, posts with higher pending payout first; paging cuts out given and higher payout posts  | 
**start_author** | **str** | author account name, if passed must be passed with start_permlink | [optional] 
**start_permlink** | **str** | post permlink of given author, point to valid post, paging mechanism | [optional] 
**limit** | **int** |  | [optional]  if omitted the server will use the default value of 20
**tag** | **str** | my (with observer) - turns on filtering for posts within communities subscribed to by observer all - same as default none/blank hive-{number} - has to point to valid community; turns on filtering for posts within given community {tag} - has to point to valid tag; turns on filtering for posts with given tag (given category in case of &#39;payout&#39; and &#39;payout_comments&#39;)  | [optional] 
**observer** | **str** | mandatory for \&quot;my\&quot; tag, points to valid account; when given supplements blacklists stats in posts and filters out posts of muted authors (with exception of \&quot;muted\&quot; sort) | [optional] 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


