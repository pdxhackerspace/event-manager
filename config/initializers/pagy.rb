# Be sure to restart your server when you modify this file.

# 24 divides evenly into the 2- and 3-column card grids used on the index pages.
Pagy::OPTIONS[:limit] = 24

# Out-of-range pages raise Pagy::RangeError; ApplicationController rescues and
# re-paginates on the last page (see pagy 43 upgrade guide).
Pagy::OPTIONS[:raise_range_error] = true
