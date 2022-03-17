def run_test(reference_node_url, test_node_url, payload, table_keys):
    import prettytable
    from requests import post
    from json import dumps

    print("Querying reference node")
    resp = post(reference_node_url, dumps(payload))

    json = resp.json()
    # print(json)
    table = prettytable.PrettyTable()
    table.field_names = table_keys
    for row in json['result']['comments']:
        table.add_row([row[key] for key in table_keys])
    print(table)

    print("Querying test node")
    resp = post(test_node_url, dumps(payload))

    json = resp.json()
    # print(json)
    table = prettytable.PrettyTable()
    table.field_names = table_keys
    for row in json['result']:
        table.add_row([row[key] for key in table_keys])
    print(table)
