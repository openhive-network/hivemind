# ListCommunitesRequestParams

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**last** | **str** | name of community; paging mechanism (cuts out this and \&quot;higher\&quot; communities, depends on chosen ranking) | [optional] 
**limit** | **int** | limit number of listed communities | [optional]  if omitted the server will use the default value of 100
**query** | **str** | when given turns on filtering for given set of words - words are looked for in \&quot;title\&quot; and \&quot;about\&quot; fields | [optional] 
**sort** | **str** |  determines order of returned communities | [optional]  if omitted the server will use the default value of "rank"
**observer** | **str** | (can be skipped or passed empty), when passed has to point to valid account used to show relation between account and community (subscribed, role and title) | [optional] 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


