from tests.unit_tests.conftest import database_connection
import hive.indexer.community as Community
import hive.indexer.accounts as Accounts

def test_community_creation_without_account(database_connection):
    try:
        Community.Community.register("hive-12345", "2020-10-10 10:10:10", 1)
    except AssertionError as ex: 
        assert str(ex) == "Account 'hive-12345' does not exist"
    ret = database_connection.query_all("SELECT * FROM hive_communities")
    assert not ret, "Result should be empty"

def test_community_creation_with_account(database_connection):
    Accounts.Accounts.setup_own_db_access(database_connection)
    Accounts.Accounts.register("hive-12345", "", "2020-10-10 10:10:10", 1)
    Accounts.Accounts.flush()
    ret = database_connection.query_all("SELECT * FROM hive_communities")
    assert ret, "Result should be not empty"
    assert len(ret) == 1, "There should be one registered community"

def test_community_set_admin(database_connection):
    Accounts.Accounts.setup_own_db_access(database_connection)
    Accounts.Accounts.register("threespeak", "", "2020-10-10 10:10:10", 1)
    Accounts.Accounts.flush()
    json = [
        "setRole",
        {
            "community":"hive-12345",
            "account":"threespeak",
            "role":"admin"
        }
    ]
    Community.CommunityOp.process_if_valid("hive-12345", json, "2020-10-10 10:10:10", 1)

    account_id = Accounts.Accounts.get_id("threespeak")
    community_id = Community.Community.get_id("hive-12345")
    ret = database_connection.query_all("SELECT * FROM hive_roles WHERE account_id=:account_id", account_id=account_id)

    assert ret, "Result should be not empty"
    assert len(ret) == 1
    assert ret[0]['account_id'] == account_id
    assert ret[0]['community_id'] == community_id

def test_community_change_props(database_connection):
    json = [
        "updateProps",
        {
            "community":"hive-12345",
            "props":{
                "title":"I like Numbers",
                "about":"Community for people that do like numbers",
                "is_nsfw":False
            }
        }
    ]
    Community.CommunityOp.process_if_valid("hive-12345", json, "2020-10-10 10:10:10", 1)
    ret = database_connection.query_all("SELECT * FROM hive_communities")
    assert ret, "Result should be not empty"
    assert len(ret) == 1, "There should be one registered community"
    assert ret[0]['title'] == "I like Numbers"
    assert ret[0]['about'] == "Community for people that do like numbers"

def test_community_subscribe(database_connection):
    json = [
        "subscribe",
        {
            "community":"hive-12345"
        }
    ]
    Community.CommunityOp.process_if_valid("threespeak", json, "2020-10-10 10:10:10", 1)
    ret = database_connection.query_all("SELECT * FROM hive_subscriptions")
    account_id = Accounts.Accounts.get_id("threespeak")
    community_id = Community.Community.get_id("hive-12345")
    assert ret, "Result should be not empty"
    assert len(ret) == 1, "There should be one subscription"
    assert ret[0]['account_id'] == account_id
    assert ret[0]['community_id'] == community_id
