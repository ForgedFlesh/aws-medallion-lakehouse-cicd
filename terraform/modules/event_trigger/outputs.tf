output "event_queue_arn" { value = aws_sqs_queue.events.arn }
output "lambda_function_name" { value = aws_lambda_function.trigger.function_name }
