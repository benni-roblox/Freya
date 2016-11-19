--//
--// * Test script for Freya Server
--// | Makes sure modules work
--//

print "Loaded Freya Server test"
local Intents, Permissions, Events, Errors
with _G.Freya
  Intents = .GetComponent "Intents"
  Permissions = .GetComponent "Permissions"
  Events = .GetComponent "Events"
  Errors = .GetComponent "Error"

print "Loaded Components"
