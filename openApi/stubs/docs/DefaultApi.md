# openapi_client.DefaultApi

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**bridge_account_notifications**](DefaultApi.md#bridge_account_notifications) | **POST** /#bridge.account_notifications | 
[**bridge_does_user_follow_any_lists**](DefaultApi.md#bridge_does_user_follow_any_lists) | **POST** /#bridge.does_user_follow_any_lists | 
[**bridge_get_account_posts**](DefaultApi.md#bridge_get_account_posts) | **POST** /#bridge.get_account_posts | 
[**bridge_get_community**](DefaultApi.md#bridge_get_community) | **POST** /#bridge.get_community | 
[**bridge_get_community_context**](DefaultApi.md#bridge_get_community_context) | **POST** /#bridge.get_community_context | 
[**bridge_get_discussion**](DefaultApi.md#bridge_get_discussion) | **POST** /#bridge.get_discussion | 
[**bridge_get_follow_list**](DefaultApi.md#bridge_get_follow_list) | **POST** /#bridge.get_follow_list | 
[**bridge_get_payout_stats**](DefaultApi.md#bridge_get_payout_stats) | **POST** /#bridge.get_payout_stats | 
[**bridge_get_post**](DefaultApi.md#bridge_get_post) | **POST** /#bridge.get_post | 
[**bridge_get_post_header**](DefaultApi.md#bridge_get_post_header) | **POST** /#bridge.get_post_header | 
[**bridge_get_profile**](DefaultApi.md#bridge_get_profile) | **POST** /#bridge.get_profile | 
[**bridge_get_ranked_posts**](DefaultApi.md#bridge_get_ranked_posts) | **POST** /#bridge.get_ranked_posts | 
[**bridge_get_relationship_between_accounts**](DefaultApi.md#bridge_get_relationship_between_accounts) | **POST** /#bridge.get_relationship_between_accounts | 
[**bridge_list_all_subscriptions**](DefaultApi.md#bridge_list_all_subscriptions) | **POST** /#bridge.list_all_subscriptions | 
[**bridge_list_communities**](DefaultApi.md#bridge_list_communities) | **POST** /#bridge.list_communities | 
[**bridge_list_community_roles**](DefaultApi.md#bridge_list_community_roles) | **POST** /#bridge.list_community_roles | 
[**bridge_list_pop_communities**](DefaultApi.md#bridge_list_pop_communities) | **POST** /#bridge.list_pop_communities | 
[**bridge_list_subscribers**](DefaultApi.md#bridge_list_subscribers) | **POST** /#bridge.list_subscribers | 


# **bridge_account_notifications**
> object bridge_account_notifications(account_notifications_request)



Lists notifications for given account

### Example

```python
import time
import openapi_client
from openapi_client.api import default_api
from openapi_client.model.account_notifications_request import AccountNotificationsRequest
from pprint import pprint
# Defining the host is optional and defaults to http://localhost:8080
# See configuration.py for a list of all supported configuration parameters.
configuration = openapi_client.Configuration(
    host = "http://localhost:8080"
)


# Enter a context with an instance of the API client
with openapi_client.ApiClient() as api_client:
    # Create an instance of the API class
    api_instance = default_api.DefaultApi(api_client)
    account_notifications_request = AccountNotificationsRequest(
        jsonrpc="2.0",
        method="bridge.account_notifications",
        params=AccountNotificationsRequestParams(
            account="blocktrades",
            min_score=25,
            last_id=1,
            limit=100,
        ),
        id=1,
    ) # AccountNotificationsRequest | required account, optional: min_score, last_id, limit

    # example passing only required values which don't have defaults set
    try:
        api_response = api_instance.bridge_account_notifications(account_notifications_request)
        pprint(api_response)
    except openapi_client.ApiException as e:
        print("Exception when calling DefaultApi->bridge_account_notifications: %s\n" % e)
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **account_notifications_request** | [**AccountNotificationsRequest**](AccountNotificationsRequest.md)| required account, optional: min_score, last_id, limit |

### Return type

**object**

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

### HTTP response details
| Status code | Description | Response headers |
|-------------|-------------|------------------|
**200** | list of notifications |  -  |

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **bridge_does_user_follow_any_lists**
> object bridge_does_user_follow_any_lists(does_user_follow_any_lists_request)



Tells if given observer follows any blacklist or mute list

### Example

```python
import time
import openapi_client
from openapi_client.api import default_api
from openapi_client.model.does_user_follow_any_lists_request import DoesUserFollowAnyListsRequest
from pprint import pprint
# Defining the host is optional and defaults to http://localhost:8080
# See configuration.py for a list of all supported configuration parameters.
configuration = openapi_client.Configuration(
    host = "http://localhost:8080"
)


# Enter a context with an instance of the API client
with openapi_client.ApiClient() as api_client:
    # Create an instance of the API class
    api_instance = default_api.DefaultApi(api_client)
    does_user_follow_any_lists_request = DoesUserFollowAnyListsRequest(
        jsonrpc="2.0",
        method="bridge.does_user_follow_any_lists",
        params=DoesUserFollowAnyListsRequestParams(
            observer="blocktrades",
        ),
        id=1,
    ) # DoesUserFollowAnyListsRequest | required observer

    # example passing only required values which don't have defaults set
    try:
        api_response = api_instance.bridge_does_user_follow_any_lists(does_user_follow_any_lists_request)
        pprint(api_response)
    except openapi_client.ApiException as e:
        print("Exception when calling DefaultApi->bridge_does_user_follow_any_lists: %s\n" % e)
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **does_user_follow_any_lists_request** | [**DoesUserFollowAnyListsRequest**](DoesUserFollowAnyListsRequest.md)| required observer |

### Return type

**object**

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

### HTTP response details
| Status code | Description | Response headers |
|-------------|-------------|------------------|
**200** | Answer whether the observer follow any list |  -  |

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **bridge_get_account_posts**
> object bridge_get_account_posts(get_account_posts_request)



Lists posts related to given account in selected way.

### Example

```python
import time
import openapi_client
from openapi_client.api import default_api
from openapi_client.model.get_account_posts_request import GetAccountPostsRequest
from pprint import pprint
# Defining the host is optional and defaults to http://localhost:8080
# See configuration.py for a list of all supported configuration parameters.
configuration = openapi_client.Configuration(
    host = "http://localhost:8080"
)


# Enter a context with an instance of the API client
with openapi_client.ApiClient() as api_client:
    # Create an instance of the API class
    api_instance = default_api.DefaultApi(api_client)
    get_account_posts_request = GetAccountPostsRequest(
        jsonrpc="2.0",
        method="bridge.get_account_posts",
        params=GetAccountPostsRequestParams(
            sort="blog",
            account="blocktrades",
            start_author="start_author_example",
            start_permlink="start_permlink_example",
            limit=20,
            observer="blocktrades",
        ),
        id=1,
    ) # GetAccountPostsRequest | required: sort, account, optional: start_author, start_permlink, limit, observer

    # example passing only required values which don't have defaults set
    try:
        api_response = api_instance.bridge_get_account_posts(get_account_posts_request)
        pprint(api_response)
    except openapi_client.ApiException as e:
        print("Exception when calling DefaultApi->bridge_get_account_posts: %s\n" % e)
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **get_account_posts_request** | [**GetAccountPostsRequest**](GetAccountPostsRequest.md)| required: sort, account, optional: start_author, start_permlink, limit, observer |

### Return type

**object**

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

### HTTP response details
| Status code | Description | Response headers |
|-------------|-------------|------------------|
**200** | List of posts  |  -  |

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **bridge_get_community**
> object bridge_get_community(community_request)



Gets community

### Example

```python
import time
import openapi_client
from openapi_client.api import default_api
from openapi_client.model.community_request import CommunityRequest
from pprint import pprint
# Defining the host is optional and defaults to http://localhost:8080
# See configuration.py for a list of all supported configuration parameters.
configuration = openapi_client.Configuration(
    host = "http://localhost:8080"
)


# Enter a context with an instance of the API client
with openapi_client.ApiClient() as api_client:
    # Create an instance of the API class
    api_instance = default_api.DefaultApi(api_client)
    community_request = CommunityRequest(
        jsonrpc="2.0",
        method="bridge.get_community",
        params=CommunityRequestParams(
            name="hive-189306",
            observer="good-karma",
        ),
        id=1,
    ) # CommunityRequest | community name and optional observer

    # example passing only required values which don't have defaults set
    try:
        api_response = api_instance.bridge_get_community(community_request)
        pprint(api_response)
    except openapi_client.ApiException as e:
        print("Exception when calling DefaultApi->bridge_get_community: %s\n" % e)
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **community_request** | [**CommunityRequest**](CommunityRequest.md)| community name and optional observer |

### Return type

**object**

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

### HTTP response details
| Status code | Description | Response headers |
|-------------|-------------|------------------|
**200** | Community result |  -  |

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **bridge_get_community_context**
> object bridge_get_community_context(community_context_request)



Gets community context

### Example

```python
import time
import openapi_client
from openapi_client.api import default_api
from openapi_client.model.community_context_request import CommunityContextRequest
from pprint import pprint
# Defining the host is optional and defaults to http://localhost:8080
# See configuration.py for a list of all supported configuration parameters.
configuration = openapi_client.Configuration(
    host = "http://localhost:8080"
)


# Enter a context with an instance of the API client
with openapi_client.ApiClient() as api_client:
    # Create an instance of the API class
    api_instance = default_api.DefaultApi(api_client)
    community_context_request = CommunityContextRequest(
        jsonrpc="2.0",
        method="bridge.get_community_context",
        params=CommunityContextRequestParams(
            name="hive-189306",
            account="good-karma",
        ),
        id=1,
    ) # CommunityContextRequest | community name and account for context

    # example passing only required values which don't have defaults set
    try:
        api_response = api_instance.bridge_get_community_context(community_context_request)
        pprint(api_response)
    except openapi_client.ApiException as e:
        print("Exception when calling DefaultApi->bridge_get_community_context: %s\n" % e)
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **community_context_request** | [**CommunityContextRequest**](CommunityContextRequest.md)| community name and account for context |

### Return type

**object**

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

### HTTP response details
| Status code | Description | Response headers |
|-------------|-------------|------------------|
**200** | Community context result |  -  |

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **bridge_get_discussion**
> object bridge_get_discussion(get_discussion_request)



Gives flattened discussion tree starting at given post.

### Example

```python
import time
import openapi_client
from openapi_client.api import default_api
from openapi_client.model.get_discussion_request import GetDiscussionRequest
from pprint import pprint
# Defining the host is optional and defaults to http://localhost:8080
# See configuration.py for a list of all supported configuration parameters.
configuration = openapi_client.Configuration(
    host = "http://localhost:8080"
)


# Enter a context with an instance of the API client
with openapi_client.ApiClient() as api_client:
    # Create an instance of the API class
    api_instance = default_api.DefaultApi(api_client)
    get_discussion_request = GetDiscussionRequest(
        jsonrpc="2.0",
        method="bridge.get_discussion",
        params=GetDiscussionRequestParams(
            author="blocktrades",
            permlink="4th-update-of-2021-on-our-hive-software-work",
            observer="gtg",
        ),
        id=1,
    ) # GetDiscussionRequest | required: author, permlink, optional: observer

    # example passing only required values which don't have defaults set
    try:
        api_response = api_instance.bridge_get_discussion(get_discussion_request)
        pprint(api_response)
    except openapi_client.ApiException as e:
        print("Exception when calling DefaultApi->bridge_get_discussion: %s\n" % e)
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **get_discussion_request** | [**GetDiscussionRequest**](GetDiscussionRequest.md)| required: author, permlink, optional: observer |

### Return type

**object**

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

### HTTP response details
| Status code | Description | Response headers |
|-------------|-------------|------------------|
**200** | List of discussion post  |  -  |

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **bridge_get_follow_list**
> object bridge_get_follow_list(get_follow_list_request)



For given observer gives directly blacklisted/muted accounts or list of blacklists/mute lists followed by observer

### Example

```python
import time
import openapi_client
from openapi_client.api import default_api
from openapi_client.model.get_follow_list_request import GetFollowListRequest
from pprint import pprint
# Defining the host is optional and defaults to http://localhost:8080
# See configuration.py for a list of all supported configuration parameters.
configuration = openapi_client.Configuration(
    host = "http://localhost:8080"
)


# Enter a context with an instance of the API client
with openapi_client.ApiClient() as api_client:
    # Create an instance of the API class
    api_instance = default_api.DefaultApi(api_client)
    get_follow_list_request = GetFollowListRequest(
        jsonrpc="2.0",
        method="bridge.get_follow_list",
        params=GetFollowListRequestParams(
            observer="blocktrades",
            follow_type="blacklisted",
        ),
        id=1,
    ) # GetFollowListRequest | required: observer, optional: follow_type

    # example passing only required values which don't have defaults set
    try:
        api_response = api_instance.bridge_get_follow_list(get_follow_list_request)
        pprint(api_response)
    except openapi_client.ApiException as e:
        print("Exception when calling DefaultApi->bridge_get_follow_list: %s\n" % e)
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **get_follow_list_request** | [**GetFollowListRequest**](GetFollowListRequest.md)| required: observer, optional: follow_type |

### Return type

**object**

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

### HTTP response details
| Status code | Description | Response headers |
|-------------|-------------|------------------|
**200** | List of blacklisted/ muted lists |  -  |

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **bridge_get_payout_stats**
> object bridge_get_payout_stats(get_payout_stats_request)



Lists communities ordered by payout with stats (total payout, number of posts and authors).

### Example

```python
import time
import openapi_client
from openapi_client.api import default_api
from openapi_client.model.get_payout_stats_request import GetPayoutStatsRequest
from pprint import pprint
# Defining the host is optional and defaults to http://localhost:8080
# See configuration.py for a list of all supported configuration parameters.
configuration = openapi_client.Configuration(
    host = "http://localhost:8080"
)


# Enter a context with an instance of the API client
with openapi_client.ApiClient() as api_client:
    # Create an instance of the API class
    api_instance = default_api.DefaultApi(api_client)
    get_payout_stats_request = GetPayoutStatsRequest(
        jsonrpc="2.0",
        method="bridge.get_follow_list",
        params=GetPayoutStatsRequestParams(
            limit=250,
        ),
        id=1,
    ) # GetPayoutStatsRequest | optional: limit

    # example passing only required values which don't have defaults set
    try:
        api_response = api_instance.bridge_get_payout_stats(get_payout_stats_request)
        pprint(api_response)
    except openapi_client.ApiException as e:
        print("Exception when calling DefaultApi->bridge_get_payout_stats: %s\n" % e)
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **get_payout_stats_request** | [**GetPayoutStatsRequest**](GetPayoutStatsRequest.md)| optional: limit |

### Return type

**object**

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

### HTTP response details
| Status code | Description | Response headers |
|-------------|-------------|------------------|
**200** | List of communities with stats. |  -  |

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **bridge_get_post**
> object bridge_get_post(get_post_request)



Gives single selected post.

### Example

```python
import time
import openapi_client
from openapi_client.api import default_api
from openapi_client.model.get_post_request import GetPostRequest
from pprint import pprint
# Defining the host is optional and defaults to http://localhost:8080
# See configuration.py for a list of all supported configuration parameters.
configuration = openapi_client.Configuration(
    host = "http://localhost:8080"
)


# Enter a context with an instance of the API client
with openapi_client.ApiClient() as api_client:
    # Create an instance of the API class
    api_instance = default_api.DefaultApi(api_client)
    get_post_request = GetPostRequest(
        jsonrpc="2.0",
        method="bridge.get_post",
        params=GetPostRequestParams(
            author="blocktrades",
            permlink="witness-report-for-blocktrades-for-last-week-of-august",
            observer="gtg",
        ),
        id=1,
    ) # GetPostRequest | required: author, permlink, optional: observer

    # example passing only required values which don't have defaults set
    try:
        api_response = api_instance.bridge_get_post(get_post_request)
        pprint(api_response)
    except openapi_client.ApiException as e:
        print("Exception when calling DefaultApi->bridge_get_post: %s\n" % e)
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **get_post_request** | [**GetPostRequest**](GetPostRequest.md)| required: author, permlink, optional: observer |

### Return type

**object**

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

### HTTP response details
| Status code | Description | Response headers |
|-------------|-------------|------------------|
**200** | Selected post |  -  |

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **bridge_get_post_header**
> object bridge_get_post_header(get_post_header_request)



Gives very basic information on given post.

### Example

```python
import time
import openapi_client
from openapi_client.api import default_api
from openapi_client.model.get_post_header_request import GetPostHeaderRequest
from pprint import pprint
# Defining the host is optional and defaults to http://localhost:8080
# See configuration.py for a list of all supported configuration parameters.
configuration = openapi_client.Configuration(
    host = "http://localhost:8080"
)


# Enter a context with an instance of the API client
with openapi_client.ApiClient() as api_client:
    # Create an instance of the API class
    api_instance = default_api.DefaultApi(api_client)
    get_post_header_request = GetPostHeaderRequest(
        jsonrpc="2.0",
        method="bridge.get_post_header",
        params=GetPostHeaderRequestParams(
            author="blocktrades",
            permlink="witness-report-for-blocktrades-for-last-week-of-august",
        ),
        id=1,
    ) # GetPostHeaderRequest | required: author, permlink

    # example passing only required values which don't have defaults set
    try:
        api_response = api_instance.bridge_get_post_header(get_post_header_request)
        pprint(api_response)
    except openapi_client.ApiException as e:
        print("Exception when calling DefaultApi->bridge_get_post_header: %s\n" % e)
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **get_post_header_request** | [**GetPostHeaderRequest**](GetPostHeaderRequest.md)| required: author, permlink |

### Return type

**object**

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

### HTTP response details
| Status code | Description | Response headers |
|-------------|-------------|------------------|
**200** | Selected post description |  -  |

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **bridge_get_profile**
> object bridge_get_profile(get_profile_request)



Gets profile

### Example

```python
import time
import openapi_client
from openapi_client.api import default_api
from openapi_client.model.get_profile_request import GetProfileRequest
from pprint import pprint
# Defining the host is optional and defaults to http://localhost:8080
# See configuration.py for a list of all supported configuration parameters.
configuration = openapi_client.Configuration(
    host = "http://localhost:8080"
)


# Enter a context with an instance of the API client
with openapi_client.ApiClient() as api_client:
    # Create an instance of the API class
    api_instance = default_api.DefaultApi(api_client)
    get_profile_request = GetProfileRequest(
        jsonrpc="2.0",
        method="bridge.get_profile",
        params=GetProfileRequestParams(
            account="blocktrades",
            observer="gtg",
        ),
        id=1,
    ) # GetProfileRequest | required account, optional: observer

    # example passing only required values which don't have defaults set
    try:
        api_response = api_instance.bridge_get_profile(get_profile_request)
        pprint(api_response)
    except openapi_client.ApiException as e:
        print("Exception when calling DefaultApi->bridge_get_profile: %s\n" % e)
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **get_profile_request** | [**GetProfileRequest**](GetProfileRequest.md)| required account, optional: observer |

### Return type

**object**

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

### HTTP response details
| Status code | Description | Response headers |
|-------------|-------------|------------------|
**200** | profile information |  -  |

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **bridge_get_ranked_posts**
> object bridge_get_ranked_posts(get_ranked_posts_request)



Lists posts depending on given ranking criteria and filters.

### Example

```python
import time
import openapi_client
from openapi_client.api import default_api
from openapi_client.model.get_ranked_posts_request import GetRankedPostsRequest
from pprint import pprint
# Defining the host is optional and defaults to http://localhost:8080
# See configuration.py for a list of all supported configuration parameters.
configuration = openapi_client.Configuration(
    host = "http://localhost:8080"
)


# Enter a context with an instance of the API client
with openapi_client.ApiClient() as api_client:
    # Create an instance of the API class
    api_instance = default_api.DefaultApi(api_client)
    get_ranked_posts_request = GetRankedPostsRequest(
        jsonrpc="2.0",
        method="bridge.get_post",
        params=GetRankedPostsRequestParams(
            sort="hot",
            start_author="start_author_example",
            start_permlink="start_permlink_example",
            limit=20,
            tag="my",
            observer="blocktrades",
        ),
        id=1,
    ) # GetRankedPostsRequest | required: sort, optional: start_author, start_permlink, limit, tag, observer

    # example passing only required values which don't have defaults set
    try:
        api_response = api_instance.bridge_get_ranked_posts(get_ranked_posts_request)
        pprint(api_response)
    except openapi_client.ApiException as e:
        print("Exception when calling DefaultApi->bridge_get_ranked_posts: %s\n" % e)
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **get_ranked_posts_request** | [**GetRankedPostsRequest**](GetRankedPostsRequest.md)| required: sort, optional: start_author, start_permlink, limit, tag, observer |

### Return type

**object**

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

### HTTP response details
| Status code | Description | Response headers |
|-------------|-------------|------------------|
**200** | Selected post  |  -  |

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **bridge_get_relationship_between_accounts**
> object bridge_get_relationship_between_accounts(get_relationship_between_accounts_request)



Tells what relations connect given accounts from the perspective of first account.

### Example

```python
import time
import openapi_client
from openapi_client.api import default_api
from openapi_client.model.get_relationship_between_accounts_request import GetRelationshipBetweenAccountsRequest
from pprint import pprint
# Defining the host is optional and defaults to http://localhost:8080
# See configuration.py for a list of all supported configuration parameters.
configuration = openapi_client.Configuration(
    host = "http://localhost:8080"
)


# Enter a context with an instance of the API client
with openapi_client.ApiClient() as api_client:
    # Create an instance of the API class
    api_instance = default_api.DefaultApi(api_client)
    get_relationship_between_accounts_request = GetRelationshipBetweenAccountsRequest(
        jsonrpc="2.0",
        method="bridge.get_relationship_between_accounts",
        params=GetRelationshipBetweenAccountsRequestParams(
            acccount1="blocktrades",
            account1="gtg",
            observer="blocktrades",
        ),
        id=1,
    ) # GetRelationshipBetweenAccountsRequest | required: account1, account2, optional: observer

    # example passing only required values which don't have defaults set
    try:
        api_response = api_instance.bridge_get_relationship_between_accounts(get_relationship_between_accounts_request)
        pprint(api_response)
    except openapi_client.ApiException as e:
        print("Exception when calling DefaultApi->bridge_get_relationship_between_accounts: %s\n" % e)
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **get_relationship_between_accounts_request** | [**GetRelationshipBetweenAccountsRequest**](GetRelationshipBetweenAccountsRequest.md)| required: account1, account2, optional: observer |

### Return type

**object**

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

### HTTP response details
| Status code | Description | Response headers |
|-------------|-------------|------------------|
**200** | Account relations |  -  |

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **bridge_list_all_subscriptions**
> object bridge_list_all_subscriptions(list_all_subscriptions_request)



Lists all community contexts from communities given account is subscribed to.

### Example

```python
import time
import openapi_client
from openapi_client.api import default_api
from openapi_client.model.list_all_subscriptions_request import ListAllSubscriptionsRequest
from pprint import pprint
# Defining the host is optional and defaults to http://localhost:8080
# See configuration.py for a list of all supported configuration parameters.
configuration = openapi_client.Configuration(
    host = "http://localhost:8080"
)


# Enter a context with an instance of the API client
with openapi_client.ApiClient() as api_client:
    # Create an instance of the API class
    api_instance = default_api.DefaultApi(api_client)
    list_all_subscriptions_request = ListAllSubscriptionsRequest(
        jsonrpc="2.0",
        method="bridge.list_all_subscriptions",
        params=ListAllSubscriptionsRequestParams(
            account="good-karma",
        ),
        id=1,
    ) # ListAllSubscriptionsRequest | points to valid account (not necessarily subscibed to any community)

    # example passing only required values which don't have defaults set
    try:
        api_response = api_instance.bridge_list_all_subscriptions(list_all_subscriptions_request)
        pprint(api_response)
    except openapi_client.ApiException as e:
        print("Exception when calling DefaultApi->bridge_list_all_subscriptions: %s\n" % e)
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **list_all_subscriptions_request** | [**ListAllSubscriptionsRequest**](ListAllSubscriptionsRequest.md)| points to valid account (not necessarily subscibed to any community) |

### Return type

**object**

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

### HTTP response details
| Status code | Description | Response headers |
|-------------|-------------|------------------|
**200** | all subscriptions list |  -  |

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **bridge_list_communities**
> object bridge_list_communities(list_communites_request)



Gets community

### Example

```python
import time
import openapi_client
from openapi_client.api import default_api
from openapi_client.model.list_communites_request import ListCommunitesRequest
from pprint import pprint
# Defining the host is optional and defaults to http://localhost:8080
# See configuration.py for a list of all supported configuration parameters.
configuration = openapi_client.Configuration(
    host = "http://localhost:8080"
)


# Enter a context with an instance of the API client
with openapi_client.ApiClient() as api_client:
    # Create an instance of the API class
    api_instance = default_api.DefaultApi(api_client)
    list_communites_request = ListCommunitesRequest(
        jsonrpc="2.0",
        method="bridge.list_communitites",
        params=ListCommunitesRequestParams(
            last="hive-189306",
            limit=100,
            query="Hive",
            sort="rank",
            observer="good-karma",
        ),
        id=1,
    ) # ListCommunitesRequest | optional parameters: last, limit, query, sort, observer

    # example passing only required values which don't have defaults set
    try:
        api_response = api_instance.bridge_list_communities(list_communites_request)
        pprint(api_response)
    except openapi_client.ApiException as e:
        print("Exception when calling DefaultApi->bridge_list_communities: %s\n" % e)
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **list_communites_request** | [**ListCommunitesRequest**](ListCommunitesRequest.md)| optional parameters: last, limit, query, sort, observer |

### Return type

**object**

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

### HTTP response details
| Status code | Description | Response headers |
|-------------|-------------|------------------|
**200** | list of Communities |  -  |

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **bridge_list_community_roles**
> object bridge_list_community_roles(list_community_roles_request)



Gets community

### Example

```python
import time
import openapi_client
from openapi_client.api import default_api
from openapi_client.model.list_community_roles_request import ListCommunityRolesRequest
from pprint import pprint
# Defining the host is optional and defaults to http://localhost:8080
# See configuration.py for a list of all supported configuration parameters.
configuration = openapi_client.Configuration(
    host = "http://localhost:8080"
)


# Enter a context with an instance of the API client
with openapi_client.ApiClient() as api_client:
    # Create an instance of the API class
    api_instance = default_api.DefaultApi(api_client)
    list_community_roles_request = ListCommunityRolesRequest(
        jsonrpc="2.0",
        method="bridge.list_community_roles",
        params=ListCommunityRolesRequestParams(
            community="hive-189306",
            last="hive-189306",
            limit=100,
        ),
        id=1,
    ) # ListCommunityRolesRequest | community name and optional observer

    # example passing only required values which don't have defaults set
    try:
        api_response = api_instance.bridge_list_community_roles(list_community_roles_request)
        pprint(api_response)
    except openapi_client.ApiException as e:
        print("Exception when calling DefaultApi->bridge_list_community_roles: %s\n" % e)
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **list_community_roles_request** | [**ListCommunityRolesRequest**](ListCommunityRolesRequest.md)| community name and optional observer |

### Return type

**object**

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

### HTTP response details
| Status code | Description | Response headers |
|-------------|-------------|------------------|
**200** | list of Community roles |  -  |

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **bridge_list_pop_communities**
> object bridge_list_pop_communities(list_pop_communites_request)



Gets community

### Example

```python
import time
import openapi_client
from openapi_client.api import default_api
from openapi_client.model.list_pop_communites_request import ListPopCommunitesRequest
from pprint import pprint
# Defining the host is optional and defaults to http://localhost:8080
# See configuration.py for a list of all supported configuration parameters.
configuration = openapi_client.Configuration(
    host = "http://localhost:8080"
)


# Enter a context with an instance of the API client
with openapi_client.ApiClient() as api_client:
    # Create an instance of the API class
    api_instance = default_api.DefaultApi(api_client)
    list_pop_communites_request = ListPopCommunitesRequest(
        jsonrpc="2.0",
        method="bridge.list_pop_communitites",
        params=ListPopCommunitesRequestParams(
            limit=25,
        ),
        id=1,
    ) # ListPopCommunitesRequest | optional parameter: limit

    # example passing only required values which don't have defaults set
    try:
        api_response = api_instance.bridge_list_pop_communities(list_pop_communites_request)
        pprint(api_response)
    except openapi_client.ApiException as e:
        print("Exception when calling DefaultApi->bridge_list_pop_communities: %s\n" % e)
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **list_pop_communites_request** | [**ListPopCommunitesRequest**](ListPopCommunitesRequest.md)| optional parameter: limit |

### Return type

**object**

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

### HTTP response details
| Status code | Description | Response headers |
|-------------|-------------|------------------|
**200** | list of Communities |  -  |

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **bridge_list_subscribers**
> object bridge_list_subscribers(list_subscribers_request)



list subscribers

### Example

```python
import time
import openapi_client
from openapi_client.api import default_api
from openapi_client.model.list_subscribers_request import ListSubscribersRequest
from pprint import pprint
# Defining the host is optional and defaults to http://localhost:8080
# See configuration.py for a list of all supported configuration parameters.
configuration = openapi_client.Configuration(
    host = "http://localhost:8080"
)


# Enter a context with an instance of the API client
with openapi_client.ApiClient() as api_client:
    # Create an instance of the API class
    api_instance = default_api.DefaultApi(api_client)
    list_subscribers_request = ListSubscribersRequest(
        jsonrpc="2.0",
        method="bridge.list_pop_communitites",
        params=ListSubscribersRequestParams(
            community="hive-189306",
            last="hive-189306",
            limit=100,
        ),
        id=1,
    ) # ListSubscribersRequest | required community, optional: last, limit

    # example passing only required values which don't have defaults set
    try:
        api_response = api_instance.bridge_list_subscribers(list_subscribers_request)
        pprint(api_response)
    except openapi_client.ApiException as e:
        print("Exception when calling DefaultApi->bridge_list_subscribers: %s\n" % e)
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **list_subscribers_request** | [**ListSubscribersRequest**](ListSubscribersRequest.md)| required community, optional: last, limit |

### Return type

**object**

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

### HTTP response details
| Status code | Description | Response headers |
|-------------|-------------|------------------|
**200** | list of Communities |  -  |

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

