def chunks(lst, n):
    """Yield successive n-sized chunks from lst."""
    for i in range(0, len(lst), n):
        yield lst[i:i + n]

def show_app_version(log, database_head_block, patch_level_data):
    from hive.version import VERSION, GIT_REVISION, GIT_DATE
    log.info("hivemind_version : %s", VERSION)
    log.info("hivemind_git_rev : %s", GIT_REVISION)
    log.info("hivemind_git_date : %s", GIT_DATE)

    log.info("database_schema_version : %s", patch_level_data['level'])
    log.info("database_patch_date : %s", patch_level_data['patch_date'])
    log.info("database_patched_to_revision : %s", patch_level_data['patched_to_revision'])
        
    log.info("database_head_block : %s", database_head_block)
