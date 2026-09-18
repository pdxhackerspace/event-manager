# Be sure to restart your server when you modify this file.

require 'pagy/extras/bootstrap'

# Out-of-range pages clamp to the last page rather than raising, so a stale or
# hand-edited ?page= never 500s.
require 'pagy/extras/overflow'
Pagy::DEFAULT[:overflow] = :last_page

# 24 divides evenly into the 2- and 3-column card grids used on the index pages.
Pagy::DEFAULT[:limit] = 24

Pagy::DEFAULT.freeze
