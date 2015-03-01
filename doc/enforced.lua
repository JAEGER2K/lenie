-- This is an example configuration file as it could be placed in /etc/lenie/enforced.lua to set
-- restrictions by the system administrator that overrule parts of the users config. You could,
-- theoretically, place the same settings in here as in rc.lua or /etc/lenie/defaults.lua, but
-- it is meant to specify performance or security related options where the sys admin should
-- have the highest authority.

-- Put process to sleep for 1 second after generating 10 posts.
-- Setting sleep_interval <= 0 disables sleeping alltogether
sleep_interval = 10
-- If sleeping is enabled, sleep_duration defines the time in seconds (only integers allowed)
sleep_duration = 1
