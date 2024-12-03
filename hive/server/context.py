import contextvars

# Create a context variable to track auto_explain state
autoexplain_enabled = contextvars.ContextVar('autoexplain_enabled', default=False)
