# coding: utf-8

from __future__ import absolute_import
import unittest

from flask import json
from six import BytesIO

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
from openapi_server.test import BaseTestCase


class TestDefaultController(BaseTestCase):
    """DefaultController integration test stubs"""

    def test_bridge_get_community(self):
        """Test case for bridge_get_community

        
        """
        community_request = {
  "method" : "bridge.get_community",
  "id" : 0,
  "jsonrpc" : "2.0",
  "params" : {
    "observer" : "good-karma",
    "name" : "hive-189306"
  }
}
        headers = { 
            'Accept': 'application/json',
            'Content-Type': 'application/json',
        }
        response = self.client.open(
            '/#bridge.get_community',
            method='POST',
            headers=headers,
            data=json.dumps(community_request),
            content_type='application/json')
        self.assert200(response,
                       'Response body is : ' + response.data.decode('utf-8'))

    def test_bridge_get_community_context(self):
        """Test case for bridge_get_community_context

        
        """
        community_context_request = {
  "method" : "bridge.get_community_context",
  "id" : 0,
  "jsonrpc" : "2.0",
  "params" : {
    "name" : "hive-189306",
    "account" : "good-karma"
  }
}
        headers = { 
            'Accept': 'application/json',
            'Content-Type': 'application/json',
        }
        response = self.client.open(
            '/#bridge.get_community_context',
            method='POST',
            headers=headers,
            data=json.dumps(community_context_request),
            content_type='application/json')
        self.assert200(response,
                       'Response body is : ' + response.data.decode('utf-8'))

    def test_bridge_list_all_subscriptions(self):
        """Test case for bridge_list_all_subscriptions

        
        """
        list_all_subscriptions_request = {
  "method" : "bridge.list_all_subscriptions",
  "id" : 0,
  "jsonrpc" : "2.0",
  "params" : {
    "account" : "good-karma"
  }
}
        headers = { 
            'Accept': 'application/json',
            'Content-Type': 'application/json',
        }
        response = self.client.open(
            '/#bridge.list_all_subscriptions',
            method='POST',
            headers=headers,
            data=json.dumps(list_all_subscriptions_request),
            content_type='application/json')
        self.assert200(response,
                       'Response body is : ' + response.data.decode('utf-8'))

    def test_bridge_list_communities(self):
        """Test case for bridge_list_communities

        
        """
        list_communites_request = {
  "method" : "bridge.list_communitites",
  "id" : 6,
  "jsonrpc" : "2.0",
  "params" : {
    "observer" : "good-karma",
    "last" : "hive-189306",
    "query" : "Hive",
    "limit" : 8,
    "sort" : "rank"
  }
}
        headers = { 
            'Accept': 'application/json',
            'Content-Type': 'application/json',
        }
        response = self.client.open(
            '/#bridge.list_communities',
            method='POST',
            headers=headers,
            data=json.dumps(list_communites_request),
            content_type='application/json')
        self.assert200(response,
                       'Response body is : ' + response.data.decode('utf-8'))

    def test_bridge_list_community_roles(self):
        """Test case for bridge_list_community_roles

        
        """
        list_community_roles_request = {
  "method" : "bridge.list_community_roles",
  "id" : 6,
  "jsonrpc" : "2.0",
  "params" : {
    "last" : "hive-189306",
    "limit" : 8,
    "community" : "hive-189306"
  }
}
        headers = { 
            'Accept': 'application/json',
            'Content-Type': 'application/json',
        }
        response = self.client.open(
            '/#bridge.list_community_roles',
            method='POST',
            headers=headers,
            data=json.dumps(list_community_roles_request),
            content_type='application/json')
        self.assert200(response,
                       'Response body is : ' + response.data.decode('utf-8'))

    def test_bridge_list_pop_communities(self):
        """Test case for bridge_list_pop_communities

        
        """
        list_pop_communites_request = {
  "method" : "bridge.list_pop_communitites",
  "id" : 6,
  "jsonrpc" : "2.0",
  "params" : {
    "limit" : 2
  }
}
        headers = { 
            'Accept': 'application/json',
            'Content-Type': 'application/json',
        }
        response = self.client.open(
            '/#bridge.list_pop_communities',
            method='POST',
            headers=headers,
            data=json.dumps(list_pop_communites_request),
            content_type='application/json')
        self.assert200(response,
                       'Response body is : ' + response.data.decode('utf-8'))

    def test_bridge_list_subscribers(self):
        """Test case for bridge_list_subscribers

        
        """
        list_subscribers_request = {
  "method" : "bridge.list_pop_communitites",
  "id" : 6,
  "jsonrpc" : "2.0",
  "params" : {
    "last" : "hive-189306",
    "limit" : 8,
    "community" : "hive-189306"
  }
}
        headers = { 
            'Accept': 'application/json',
            'Content-Type': 'application/json',
        }
        response = self.client.open(
            '/#bridge.list_subscribers',
            method='POST',
            headers=headers,
            data=json.dumps(list_subscribers_request),
            content_type='application/json')
        self.assert200(response,
                       'Response body is : ' + response.data.decode('utf-8'))


if __name__ == '__main__':
    unittest.main()
