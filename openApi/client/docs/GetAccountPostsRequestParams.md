# GetAccountPostsRequestParams

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**sort** | **str** | ### Sort order: blog - top posts authored by given account (excluding posts to communities - unless explicitely reblogged) plus reblogs ranked by creation/reblog time   feed - top posts from blogs of accounts that given account is following ranked by creation/reblog time, not older than last month   posts - op posts authored by given account, newer first   comments - replies authored by given account, newer first   replies - replies to posts of given account, newer first   payout - all posts authored by given account that were not yet cashed out  | 
**account** | **str** | account name, points to valid account | 
**start_author** | **str** | author account name, if passed must be passed with start_permlink | [optional] 
**start_permlink** | **str** | post permlink of given author, point to valid post, paging mechanism | [optional] 
**limit** | **int** |  | [optional]  if omitted the server will use the default value of 20
**observer** | **str** | ignored for blog, feed and replies, otherwise when passed has to point to valid account used to fill blacklist stats and mark posts of authors blacklisted by observer, at this time ignored | [optional] 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


