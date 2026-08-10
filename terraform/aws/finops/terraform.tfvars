# -----------------------------------------------------------------------------
# AWS FinOps — replace placeholders before first apply (spinup applies this module).
# budget_alert_email must be an inbox you can confirm for SNS subscription emails.
# aws_account_id: use your real 12-digit ID, e.g. $(aws sts get-caller-identity --query Account --output text)
# -----------------------------------------------------------------------------

cost_center = "ENG-001"
team        = "engineering"
owner       = "platform-team"

budget_alert_email = "REPLACE_WITH_YOUR_ALERT_EMAIL"
aws_account_id     = "000000000000"
