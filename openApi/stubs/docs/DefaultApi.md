# openapi_client.DefaultApi

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**bridge_account_notifications**](DefaultApi.md#bridge_account_notifications) | **POST** /#bridge.account_notifications | 
[**bridge_does_user_follow_any_lists**](DefaultApi.md#bridge_does_user_follow_any_lists) | **POST** /#bridge.does_user_follow_any_lists | 
[**bridge_get_community**](DefaultApi.md#bridge_get_community) | **POST** /#bridge.get_community | 
[**bridge_get_community_context**](DefaultApi.md#bridge_get_community_context) | **POST** /#bridge.get_community_context | 
[**bridge_get_profile**](DefaultApi.md#bridge_get_profile) | **POST** /#bridge.get_profile | 
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

