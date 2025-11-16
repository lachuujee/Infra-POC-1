# Terragrunt configuration

# ... (previous content)

modules_dir = coalesce(get_env("MODULES_DIR", ""), "modules/v1")

# ... (subsequent content)