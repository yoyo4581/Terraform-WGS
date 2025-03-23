import json
import urllib.parse
import boto3
import os

print('Loading function')

# Initialize the AWS services
ecs_client = boto3.client('ecs')
s3_client = boto3.client('s3')

# ECS cluster and task definition parameters
CLUSTER_NAME = 'snakemake-fargate-cluster'  # Update with your ECS Fargate cluster name
TASK_DEFINITION = 'snakemake-fargate-task'  # Update with your ECS task definition
SUBNETS = ['subnet-07c98c8499489cd1f']  # Update with your subnet ID
SECURITY_GROUPS = ['sg-05fdfa4cb96b25fd6']  # Update with your security group ID

def lambda_handler(event, context):
    print("Received event: " + json.dumps(event, indent=2))

    # Get the bucket and object key from the S3 event
    bucket = event['Records'][0]['s3']['bucket']['name']
    key = urllib.parse.unquote_plus(event['Records'][0]['s3']['object']['key'], encoding='utf-8')
    
    try:
        # Get the Snakefile from S3
        response = s3_client.get_object(Bucket=bucket, Key=key)
        print("CONTENT TYPE: " + response['ContentType'])
        
        # Prepare the command to run Snakemake (example)
        
        snakemake_command = f"snakemake --tibanna --profile profiles/tibanna --default-remote-prefix="
        
        # # Run the ECS Fargate task with overridden command
        # run_task_response = ecs_client.run_task(
        #     cluster=CLUSTER_NAME,
        #     launchType='FARGATE',
        #     taskDefinition=TASK_DEFINITION,
        #     networkConfiguration={
        #         'awsvpcConfiguration': {
        #             'subnets': SUBNETS,
        #             'securityGroups': SECURITY_GROUPS,
        #             'assignPublicIp': 'ENABLED'
        #         }
        #     },
        #     overrides={
        #         'containerOverrides': [
        #             {
        #                 'name': 'snakemake-runner',  # Container name in your task definition
        #                 "command": [
        #                     "sh",
        #                     "-c",
        #                     "aws s3 cp s3://your-snakefile-bucket/snakemake_workflow/ /snakemake_workflow/ --recursive && snakemake --tibanna --default-remote-prefix=s3://your-input-output-bucket/subdir --retries 3"
        #                 ]  # Override with Snakemake command
        #             }
        #         ]
        #     }
        # )
        
        # # Print the response for debugging
        # print("Run Task Response: ", json.dumps(run_task_response, indent=2))
        
        return {
            'statusCode': 200,
            'body': json.dumps('Task started successfully!')
        }
    
    except Exception as e:
        print(f"Error: {str(e)}")
        raise e
