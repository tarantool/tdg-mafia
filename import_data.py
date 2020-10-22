#!/usr/bin/env python3

import requests
import json


url = "http://localhost:8081"



def send_graphql(query, variables={}):
    request = {"query": query, "variables": variables}
    headers = {"schema": "default"}
    r = requests.post(url + "/graphql", json=request, headers=headers, timeout=10)
    r.raise_for_status()

    json_data = r.json()
    if 'errors' in json_data:
        print(json_data['errors'])
    return json_data






if __name__ == '__main__':
    with open('data.json') as f:
        data = json.loads(f.read())

    for space, entries in data.items():
        for entry in entries:
            send_graphql(
"""
mutation($obj: %sInput) {
  %s(insert: $obj) {
  }
}
""" % (space, space),
                {"obj": entry}
            )
