# Project Information
project = "RSVP"
version = "v4"
author = "ManEatingApe"
copyright = "2020, ManEatingApe"

# Exclude RST source files from output
html_copy_source = False

# Warn about references where target cannot be found
nitpicky = True

# Add logo to sidebar
html_logo = "images/rsvp_logo_white_small.png"

# Use ReadTheDocs theme
import sphinx_rtd_theme
extensions = ["sphinx_rtd_theme"]
html_theme = "sphinx_rtd_theme"

# Customize Theme
html_theme_options = {
    "logo_only": True
}