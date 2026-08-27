# Looks up the existing public hosted zone for the root domain - this repo
# doesn't create or manage the zone itself (that's a one-time, account-level
# thing usually done outside any single app's Terraform), only a record
# inside it.
data "aws_route53_zone" "this" {
  name         = var.domain_name
  private_zone = false
}

# An ALIAS record (Route53's AWS-specific extension of CNAME/A) rather than
# a plain CNAME: it's free to query, has no TTL to manage, resolves faster,
# and - unlike a CNAME - would also work if this were ever pointed at the
# apex domain instead of a subdomain.
resource "aws_route53_record" "app" {
  zone_id = data.aws_route53_zone.this.zone_id
  name    = var.record_name
  type    = "A"

  alias {
    name                   = var.alb_dns_name
    zone_id                = var.alb_zone_id
    evaluate_target_health = true # Route53 stops answering with this record if the ALB itself is reporting unhealthy
  }
}
