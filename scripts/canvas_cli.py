#!/usr/bin/python3

import click
import requests
import pprint
import json

pp = pprint.PrettyPrinter(indent=4)

@click.group()
@click.argument("secrets_file", type=click.File("r"), metavar="SECRETS")
@click.option("--server", default="http://localhost", help="Server URL. Defaults to http://localhost.")
@click.option("--account", type=click.INT, default=1, help="Account ID. Defaults to 1.")
def api(secrets_file, server, account):
  """A CLI to access the Canvas REST API 
  
  SECRETS - A JSON file containing tokens and keys
  """
  global secrets
  global headers
  global base_url

  secrets = json.load(secrets_file)
  if "token" not in secrets:
    print("Secrets file does not contain token. Please go to canvas profile settings and add an Approved Integration token. Put the token in your secrets file with the key 'token'.")
    exit(1)
  headers = {"Authorization":"Bearer " + secrets["token"]}
  base_url = server + "/api/v1/accounts/" + str(account) + "/"
  pass

@api.group()
def auth():
  """Use the Authentication Providers API
  """
  pass

@auth.command()
def list():
  """Lists the current authentication providers
  """
  print("Listing authentication providers...")
  url = base_url + "authentication_providers"
  response = requests.get(url, headers=headers).json()
  for authentication_provider in response:
    print("[{}] {}".format(authentication_provider["position"], authentication_provider["auth_type"]))
  exit(0)

@auth.command()
@click.argument("auth-type", type=click.Choice(["microsoft"]))
@click.option("--position", type=click.INT, default=1, help="Position for new auth provider. Defaults to 1.")
@click.option("--login_attribute", default="preferred_username", help="Which login attribute to use. Defaults to preferred_username.")
def add(auth_type, position, login_attribute):
  """Adds an authentication provider

  AUTH_TYPE Which type of authentication to add (microsoft)
  """
  print("Adding {} authentication at position {}...".format(auth_type, position))
  url = base_url + "authentication_providers"
  if (auth_type == "microsoft"):
    if "microsoft_application_id" not in secrets:
      print("Secrets file does not contain microsoft_application_id")
      exit(1)
    if "microsoft_application_secret" not in secrets:
      print("Secrets file does not contain microsoft_application_secret")
      exit(1)
    data = {
      "application_id": secrets["microsoft_application_id"],
      "application_secret": secrets["microsoft_application_secret"],
      "auth_type": auth_type,
      "login_attribute": login_attribute,
      "position": position
    }
    pp.pprint(data)
  response = requests.post(url, headers=headers, data=data).json()
  pp.pprint(response)

@api.group()
def sis():
  """Use the SIS imports API
  """
  pass

@sis.command()
def list(): 
  """Lists recent SIS imports
  """
  print("Listing recent SIS imports...")
  url = base_url + "sis_imports"
  response = requests.get(url, headers=headers).json()
  for sis_import in response['sis_imports']:
    print("id: {}, workflow_state: {}, progress: {}".format(sis_import["id"], sis_import["workflow_state"], sis_import["progress"]))

@sis.command()
@click.argument("id", type=click.INT)
def details(id):
  """Print details about a SIS import
  """
  print("Printing details for SIS import {}...".format(id))
  url = base_url + "sis_imports/" + str(id)
  response = requests.get(url, headers=headers).json()
  pp.pprint(response)

@sis.command(name="import")
@click.argument("file", type=click.File(mode="rb"))
def sis_import(file):
  """Start a SIS import
  """
  print("Starting SIS import...")
  url = base_url + "sis_imports"
  attachment = {'attachment': file}
  response = requests.post(url, files=attachment, headers=headers).json()
  pp.pprint(response)

api()
