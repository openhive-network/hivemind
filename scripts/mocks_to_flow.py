# This script parses a json mock file and outputs a flow.txt file
import json

def parse_custom_json(op):
    data = json.loads(op['json'].replace('\n', r'\n'))
    if data[0] == 'subscribe' or data[0] == 'unsubscribe':
        account = op['required_posting_auths'][0]
        return r'custom_json_operation("%s" -> "%s")' % (account, json.dumps(data).replace('"', r'\"'))
    elif data[0] == 'updateProps':
        props = json.dumps(data[1]['props']).replace('"', r'\"')
        return r'custom_json_operation("[\"updateProps\",{\"community\":\"%s\",\"props\":%s}]")' % (data[1]['community'], props)
    else:
        return 'custom_json_operation("%s")' % (json.dumps(data).replace('"', r'\"'))


def parse_op(op):
    if op['type'] == 'account_create_operation':
        return 'account_create_operation( `{}` )'.format(op['value']['new_account_name'])
    elif op['type'] == 'comment_operation':
        return 'comment_operation( `{}`, `{}`,`{}`)'.format(op['value']['parent_permlink'], op['value']['author'], op['value']['permlink'])
    elif op['type'] == 'transfer_operation':
        return 'transfer_operation( `{}`, `{}`, `{}`, `{}` )'.format(op['value']['from'], op['value']['to'], op['value']['amount'], op['value']['memo'])
    elif op['type'] == 'custom_json_operation':
        return parse_custom_json(op['value'])
    elif op['type'] == 'custom_json_operation':
        return parse_custom_json(op['value'])
    elif op['type'] == 'account_update2_operation':
        json_metadata = json.dumps(op['value']['json_metadata'].replace('\n', '\\n')).replace('"', '\"')
        return 'transfer_operation( `{}`, `{}`, `{}`)'.format(op['value']['account'], json_metadata, op['value']['posting_json_metadata'])
    elif op['type'] == 'delete_comment_operation':
        return 'delete_comment_operation( `{}`, `{}`)'.format(op['value']['author'], op['value']['permlink'])
    elif op['type'] == 'vote_operation':
        return 'delete_comment_operation(`{}` -> `{}`, `{}`, `{}`)'.format(op['value']['voter'], op['value']['author'], op['value']['permlink'], op['value']['weight'])
    else:
        raise 'operation type not known'

if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser()

    parser.add_argument("file", type=str, help="Path of the mock file")

    args = parser.parse_args()

    f = open(args.file)
    data = json.load(f)
    flow_str = ''
    for block_id in data:
        flow_str += '***block {}***\n'.format(block_id)
        operations = data[block_id]['transactions'][0]['operations']
        for op in operations:
            flow_str += parse_op(op) + '\n'
    print(flow_str)