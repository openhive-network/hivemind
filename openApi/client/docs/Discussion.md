# Discussion

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**active_votes** | [**ActiveVotes**](ActiveVotes.md) |  | 
**author** | **str** | account name of the post&#39;s author | 
**author_payout_value** | **str** | HBD paid to the author of the post | 
**author_reputation** | **float** | author&#39;s reputation score | 
**beneficiaries** | [**Beneficiares**](Beneficiares.md) |  | 
**blacklists** | **[str]** |  | 
**body** | **str** | post content | 
**category** | **str** | post category | 
**children** | **int** | number of children comments | 
**created** | **datetime** | creation date | 
**curator_payout_value** | **str** | amount of HBD paid to curators | 
**depth** | **int** | nesting level | 
**is_paidout** | **bool** | information whether the post has been paid | 
**json_metadata** | **{str: (bool, date, datetime, dict, float, int, list, str, none_type)}** |  | 
**max_accepted_payout** | **str** | maximal possible payout | 
**net_rshares** | **int** | netto rshares, result of rshares allocations | 
**parent_author** | **str** | account name of parent post author | 
**parent_permlink** | **str** | post&#39;s permlink of parent post | 
**payout** | **float** | amount of payout | 
**payout_at** | **datetime** | date of payout | 
**pending_payout_value** | **str** | pending or paid amount | 
**percent_hbd** | **int** | percent of HBD, 1000 &#x3D; 100% | 
**permlink** | **str** | post&#39;s permlink | 
**post_id** | **int** | id of the post, created from the author and the permlink | 
**promoted** | **str** | amount of HBD if post is promoted | 
**replies** | **[str]** |  | 
**stats** | [**GetPostStats**](GetPostStats.md) |  | 
**title** | **str** | post title | 
**updated** | **datetime** | date of update | 
**url** | **str** | end of the url to the post, contains category, author and permlink | 
**author_role** | **str** | author&#39;s community role (if post is in community) | [optional] 
**author_title** | **str** | author&#39;s community title (if post is in community) | [optional] 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


