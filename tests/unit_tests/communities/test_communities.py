import hive.indexer.community as Community
import hive.indexer.accounts as Accounts

def test_community_creation_without_account(database_connection):
    try:
        Community.Community.register("hive-12345", "2020-10-10 10:10:10", 1)
    except AssertionError as ex: 
        assert str(ex) == "Account 'hive-12345' does not exist"
    ret = database_connection.query_one("SELECT * FROM hive_communities")
    assert ret is None, "Result should be none"

def test_community_creation_with_account(database_connection):
    Accounts.Accounts.setup_own_db_access(database_connection)
    Accounts.Accounts.register("hive-12345", "", "2020-10-10 10:10:10", 1)
    Accounts.Accounts.flush()
    ret = database_connection.query_one("SELECT * FROM hive_communities")
    assert ret is not None, "Result should be not none"
