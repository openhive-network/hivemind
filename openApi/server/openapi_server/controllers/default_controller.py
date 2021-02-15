import connexion
import six

from openapi_server.models.community_context_request import CommunityContextRequest  # noqa: E501
from openapi_server.models.community_request import CommunityRequest  # noqa: E501
from openapi_server.models.list_all_subscriptions_request import ListAllSubscriptionsRequest  # noqa: E501
from openapi_server.models.list_communites_request import ListCommunitesRequest  # noqa: E501
from openapi_server.models.list_community_roles_request import ListCommunityRolesRequest  # noqa: E501
from openapi_server.models.list_pop_communites_request import ListPopCommunitesRequest  # noqa: E501
from openapi_server.models.list_subscribers_request import ListSubscribersRequest  # noqa: E501
from openapi_server.models.one_of_community_context_error_message import OneOfCommunityContextErrorMessage  # noqa: E501
from openapi_server.models.one_of_community_error_message import OneOfCommunityErrorMessage  # noqa: E501
from openapi_server.models.one_of_list_community_error_message import OneOfListCommunityErrorMessage  # noqa: E501
from openapi_server.models.one_ofarray_error_message import OneOfarrayErrorMessage  # noqa: E501
from openapi_server import util


def bridge_get_community(community_request):  # noqa: E501
    """bridge_get_community

    Gets community # noqa: E501

    :param community_request: community name and optional observer
    :type community_request: dict | bytes

    :rtype: OneOfCommunityErrorMessage
    """
    if connexion.request.is_json:
        community_request = CommunityRequest.from_dict(connexion.request.get_json())  # noqa: E501
    return 'do some magic!'


def bridge_get_community_context(community_context_request):  # noqa: E501
    """bridge_get_community_context

    Gets community context # noqa: E501

    :param community_context_request: community name and account for context
    :type community_context_request: dict | bytes

    :rtype: OneOfCommunityContextErrorMessage
    """
    if connexion.request.is_json:
        community_context_request = CommunityContextRequest.from_dict(connexion.request.get_json())  # noqa: E501
    return 'do some magic!'


def bridge_list_all_subscriptions(list_all_subscriptions_request):  # noqa: E501
    """bridge_list_all_subscriptions

    Lists all community contexts from communities given account is subscribed to. # noqa: E501

    :param list_all_subscriptions_request: points to valid account (not necessarily subscibed to any community)
    :type list_all_subscriptions_request: dict | bytes

    :rtype: OneOfarrayErrorMessage
    """
    if connexion.request.is_json:
        list_all_subscriptions_request = ListAllSubscriptionsRequest.from_dict(connexion.request.get_json())  # noqa: E501
    return 'do some magic!'


def bridge_list_communities(list_communites_request):  # noqa: E501
    """bridge_list_communities

    Gets community # noqa: E501

    :param list_communites_request: optional parameters: last, limit, query, sort, observer
    :type list_communites_request: dict | bytes

    :rtype: OneOfListCommunityErrorMessage
    """
    if connexion.request.is_json:
        list_communites_request = ListCommunitesRequest.from_dict(connexion.request.get_json())  # noqa: E501
    return 'do some magic!'


def bridge_list_community_roles(list_community_roles_request):  # noqa: E501
    """bridge_list_community_roles

    Gets community # noqa: E501

    :param list_community_roles_request: community name and optional observer
    :type list_community_roles_request: dict | bytes

    :rtype: OneOfarrayErrorMessage
    """
    if connexion.request.is_json:
        list_community_roles_request = ListCommunityRolesRequest.from_dict(connexion.request.get_json())  # noqa: E501
    return 'do some magic!'


def bridge_list_pop_communities(list_pop_communites_request):  # noqa: E501
    """bridge_list_pop_communities

    Gets community # noqa: E501

    :param list_pop_communites_request: optional parameter: limit
    :type list_pop_communites_request: dict | bytes

    :rtype: OneOfarrayErrorMessage
    """
    if connexion.request.is_json:
        list_pop_communites_request = ListPopCommunitesRequest.from_dict(connexion.request.get_json())  # noqa: E501
    return 'do some magic!'


def bridge_list_subscribers(list_subscribers_request):  # noqa: E501
    """bridge_list_subscribers

    list subscribers # noqa: E501

    :param list_subscribers_request: required community, optional: last, limit
    :type list_subscribers_request: dict | bytes

    :rtype: OneOfarrayErrorMessage
    """
    if connexion.request.is_json:
        list_subscribers_request = ListSubscribersRequest.from_dict(connexion.request.get_json())  # noqa: E501
    return 'do some magic!'
