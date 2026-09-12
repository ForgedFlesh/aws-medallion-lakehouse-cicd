import importlib.util
"""
importlib is Python's import system.
Normally you write:
import glue_utils
But your file is buried here:
terraform/assets/common/glue_utils.py
and that directory isn't necessarily a normal Python package.
So we use importlib.util to manually load that .py file from its exact path.
"""
import sys
import types
"""
which lets us create fake Python modules ourselves.
Example:
fake_boto3 = types.ModuleType("boto3")
creates an object that behaves like a module named boto3.
"""
from pathlib import Path
from unittest.mock import MagicMock, patch
"""
A MagicMock is a fake object that:

accepts function calls
remembers how it was called
lets us inspect arguments later
can return fake values
For example:
mock = MagicMock()
mock("hello", age=25)
Later:
mock.call_args
remembers:
"hello"
age=25
This is exactly how we'll inspect DynamoDB calls.
"""

import pytest
"""
pytest discovers functions beginning with:
test_
and also automatically gives us fixtures such as:
monkeypatch
"""
#table = boto3.resource("dynamodb").Table(table_name)
"""
REAL boto3                   FAKE boto3

boto3                        fake_boto3
  └── resource()               └── resource()
      real SDK call                MagicMock

"""


# ---------------------------------------------------------
# Fake AWS modules
# ---------------------------------------------------------
# GitHub CI will not have the AWS Glue Python runtime.
# We only want to unit-test OUR logic, not AWS itself.
fake_boto3 = types.ModuleType("boto3")
fake_boto3.resource = MagicMock()

#from awsglue.utils import getResolvedOptions
"""
This establishes the relationship:

awsglue
   └── utils
       └── getResolvedOptions
"""
fake_awsglue=types.ModuleType("awsglue")
fake_awsglue_utils = types.ModuleType("awsglue.utils")
fake_awsglue_utils.getResolvedOptions=MagicMock()
fake_awsglue.utils=fake_awsglue_utils

#Put the fake modules into Python's module registry
sys.modules["boto3"]=fake_boto3
sys.modules["awsglue"] = fake_awsglue
sys.modules["awsglue.utils"] = fake_awsglue_utils

# ---------------------------------------------------------
# Load glue_utils.py directly
# ---------------------------------------------------------

PROJECT_ROOT=Path(__file__).resolve().parents[1]

GLUE_UTILS_PATH = (PROJECT_ROOT/ "terraform"/ "assets"/ "common"/ "glue_utils.py")
#PROJECT_ROOT/terraform/assets/common/glue_utils.py

spec = importlib.util.spec_from_file_location(
    "glue_utils",
    GLUE_UTILS_PATH,
)
#this is just the specification,i want to import a python module and name it glue_utils from this path

glue_utils = importlib.util.module_from_spec(spec)
#This creates an actual module object based on that specification.

spec.loader.exec_module(glue_utils)
#now we have actually loaded the module and now have write_audit,fail_audit,utc_now functions of the glue util are available
"""
And because we already modified sys.modules, when that file executes:
import boto3 it gets our fake boto3.
1. create fake boto3
2. put fake boto3 in sys.modules
3. THEN load glue_utils.py
"""

#monkeypatch is a pytest tool for temporarily replacing something real with something fake during one test.
def test_write_audit_running(monkeypatch):
    table = MagicMock()
    #our fake dynamoDb table
    dynamodb= MagicMock()
    dynamodb.Table.return_value=table
    #when we will call dynamodb.Table() we should get our fake table

    monkeypatch.setattr(glue_utils.boto3,"resource",MagicMock(return_value=dynamodb),)
    """
    production code does:
    boto3.resource("dynamodb") We replace that function temporarily.Instead of real behavior:
    boto3.resource("dynamodb")
    → real AWS resource
    during this test:
    boto3.resource("dynamodb")
    → fake dynamodb MagicMock

    """

    monkeypatch.setattr(
    glue_utils,
    "utc_now",
    lambda: "2026-09-11T10:00:00+00:00",
    )
    """
    utc_now()
    returns the real current timestamp.
    we are trying to change it with a constant value,lambda is like a small function which returns the value
    This is called making a test deterministic.
    """

    glue_utils.write_audit(
        table_name="audit-table",
        run_id="run-123",
        stage="ingestion",
        status="RUNNING",
    )
    """
    Because: status == "RUNNING"
    it enters:
    if status == "RUNNING":
    inside glue_utils.py.Eventually production code executes:
    table.update_item(...)
    Except table is our MagicMock.
    So nothing reaches AWS.
    MagicMock simply records:
    update_item() was called with these values.
       """

    table.update_item.assert_called_once()
    #Did update_item() get called exactly one time?

    call=table.update_item.call_args.kwargs
    """
    “MagicMock, give me the keyword arguments from the last time update_item() was called.”

    So call becomes an ordinary Python dictionary roughly like:

    {
        "Key": {
            "run_id": "run-123",
            "stage": "ingestion",
        },
        "UpdateExpression": "...",
        "ExpressionAttributeNames": {
            "#status": "status",
        },
        "ExpressionAttributeValues": {
            ":status": "RUNNING",
            ":updated_at": "...",
            ":started_at": "...",
        },
    }
    
    """

    assert call["Key"] == {
    "run_id": "run-123",
    "stage": "ingestion",
    }
    #Did our production code create the correct DynamoDB primary key?
    #we are checking that on our last call to the table.update_item() was the correct key was passed to that update_item function



    assert (
        call["ExpressionAttributeValues"][":status"]
        == "RUNNING"
    )

    assert (
        call["ExpressionAttributeValues"][":started_at"]
        == "2026-09-11T10:00:00+00:00"
    )

    assert "if_not_exists" in call["UpdateExpression"]

    assert (
        "REMOVE completed_at, error_message"
        in call["UpdateExpression"]
    )

   #basically we are checking with the above assert conditions that whether during 
   # the call of table.update_item() the correct values were used during the call


def test_write_audit_with_metrics(monkeypatch):
    table=MagicMock()
    dynamodb=MagicMock()

    dynamodb.Table.return_value=table

    monkeypatch.setattr(glue_utils.boto3,"resource",MagicMock(return_value=dynamodb),)

    monkeypatch.setattr(
    glue_utils,
    "utc_now",
    lambda: "2026-09-11T10:00:00+00:00",
    )

    glue_utils.write_audit(
        table_name="audit-table",
        run_id="run-123",
        stage="transform",
        status="SUCCEEDED",
        metrics={
            "rows_read": 100,
            "success": True,
            "file": "orders.csv",
        },
    )

    table.update_item.assert_called_once()
    call=table.update_item.call_args.kwargs
    #magicmock remember the last call,it returns the arguments passed to it in form of a dictonary
    metrics=call["ExpressionAttributeValues"][":metrics"]

    assert metrics["rows_read"] == 100
    assert metrics["success"] == 1
    assert metrics["file"] == "orders.csv"

    assert (
        call["ExpressionAttributeNames"]["#metrics"]
        == "metrics"
    )

# ---------------------------------------------------------
# TEST 3
# Error messages must be capped at 3000 characters
# ---------------------------------------------------------

def test_error_message_is_truncated(monkeypatch):

    table = MagicMock()

    dynamodb = MagicMock()
    dynamodb.Table.return_value = table

    monkeypatch.setattr(
        glue_utils.boto3,
        "resource",
        MagicMock(return_value=dynamodb),
    )

    monkeypatch.setattr(
        glue_utils,
        "utc_now",
        lambda: "2026-09-11T10:00:00+00:00",
    )

    long_error = "X" * 5000

    glue_utils.write_audit(
        table_name="audit-table",
        run_id="run-123",
        stage="transform",
        status="FAILED",
        error_message=long_error,
    )

    call = table.update_item.call_args.kwargs

    stored_error = call[
        "ExpressionAttributeValues"
    ][":error_message"]

    assert len(stored_error) == 3000
#in my common python glue_util.py the fail_audit() does not call dynamo db itself,we call write_audit()..so we create a 
#fake write_audit for this test 

def test_fail_audit(monkeypatch):

    mock_write_audit = MagicMock()

    monkeypatch.setattr(
        glue_utils,
        "write_audit",
        mock_write_audit,
    )

    try:
        raise ValueError("Something went wrong")
    except ValueError as exc:

        glue_utils.fail_audit(
            table_name="audit-table",
            run_id="run-123",
            stage="transform",
            exc=exc,
        )

    mock_write_audit.assert_called_once()

    args = mock_write_audit.call_args.args
    kwargs = mock_write_audit.call_args.kwargs

    assert args[0] == "audit-table"
    assert args[1] == "run-123"
    assert args[2] == "transform"
    assert args[3] == "FAILED"

    assert "ValueError" in kwargs["error_message"]
    assert "Something went wrong" in kwargs["error_message"]







