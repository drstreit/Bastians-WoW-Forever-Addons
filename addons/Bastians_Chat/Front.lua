-- Bastian's Chat, the layout the other parts talk to (plan-chat-two-decks.md V38): the two decks,
-- or until V35 the Inbox of version 3. The request bar, People, the menus and the feed call
-- `ns.Front.ShowPerson(...)` and reach whichever window shows.
local _, ns = ...

ns.Front = setmetatable({}, {
  __index = function(_, key)
    local decks = ns.Decks
    if decks and ns.View and ns.View.LayoutKind() == "decks" and decks[key] ~= nil then
      return decks[key]
    end
    return ns.Inbox[key]
  end,
})
