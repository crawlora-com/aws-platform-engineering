
output "db_access_sg_id" {
  value = var.config.db_access_sg_exists ? var.config.db_access_sg_id : aws_security_group.db_access_sg[0].id
}

output "rds_address" {
  value = aws_db_instance.rds.address
}

output "db_port" {
  value = aws_db_instance.rds.port
}

output "db_sg_id" {
  value = aws_security_group.rds_sg.id
}

output "db_name" {
  value = aws_db_instance.rds.db_name
}

output "db_instance_identifier" {
  value = aws_db_instance.rds.identifier
}
/*
output "database_uri" {
  value = "postgresql://${aws_db_instance.rds.username}:${var.settings.db_password}@${aws_db_instance.rds.address}:${aws_db_instance.rds.port}/${aws_db_instance.rds.db_name}"
}
*/
