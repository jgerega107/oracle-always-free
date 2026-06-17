output "instance_id" {
  description = "OCID of the Always Free ARM instance."
  value       = oci_core_instance.this.id
}

output "instance_display_name" {
  description = "Display name of the instance."
  value       = oci_core_instance.this.display_name
}

output "public_ip" {
  description = "Public IPv4 address of the instance, if assigned."
  value       = try(oci_core_instance.this.public_ip, null)
}

output "private_ip" {
  description = "Private IPv4 address of the instance."
  value       = oci_core_instance.this.private_ip
}

output "selected_image_id" {
  description = "OCID of the selected latest Oracle Linux image."
  value       = data.oci_core_images.oracle_linux.images[0].id
}

output "selected_image_name" {
  description = "Display name of the selected latest Oracle Linux image."
  value       = data.oci_core_images.oracle_linux.images[0].display_name
}

output "availability_domain" {
  description = "Availability domain used by the instance."
  value       = local.availability_domain
}

output "budget_id" {
  description = "OCID of the monthly budget used for cost alerts."
  value       = oci_budget_budget.this.id
}
