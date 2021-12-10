import parser


def test_args_parsing():
    args = parser.init_argparse(['--desc', 'Test description',
                                 '--exec-env-desc', 'environment',
                                 '--server-name', 'server',
                                 '--app-version', '1.00',
                                 '--testsuite-version', '2.00',
                                 '-f', 'input/sample_with_mixed_lines.txt',
                                 '-db', 'testurl'])

    assert args.desc == 'Test description'
    assert args.exec_env_desc == 'environment'
    assert args.server_name == 'server'
    assert args.app_version == '1.00'
    assert args.testsuite_version == '2.00'
    assert args.file == 'input/sample_with_mixed_lines.txt'
    assert args.database_url == 'testurl'
