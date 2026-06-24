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

output "vcn_ipv6_cidr_blocks" {
  description = "Oracle-allocated IPv6 /56 prefixes on the VCN when IPv6 is enabled."
  value       = oci_core_vcn.this.ipv6cidr_blocks
}

output "subnet_ipv6_cidr_block" {
  description = "IPv6 /64 prefix assigned to the public subnet when IPv6 is enabled."
  value       = try(oci_core_subnet.public.ipv6cidr_block, null)
}

data "oci_core_image" "selected" {
  image_id = oci_core_instance.this.source_details[0].source_id
}

output "selected_image_id" {
  description = "OCID of the Oracle Linux image used by the instance."
  value       = oci_core_instance.this.source_details[0].source_id
}

output "selected_image_name" {
  description = "Display name of the Oracle Linux image used by the instance."
  value       = data.oci_core_image.selected.display_name
}

output "availability_domain" {
  description = "Availability domain used by the instance."
  value       = local.availability_domain
}

output "budget_id" {
  description = "OCID of the monthly budget used for cost alerts."
  value       = oci_budget_budget.this.id
}
