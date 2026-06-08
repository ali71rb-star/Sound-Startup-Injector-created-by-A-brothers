require "import"
-- STARTUP_SOUND_INJECTOR_START
pcall(function()
    if startup_sound_mp ~= nil then
        pcall(function() startup_sound_mp.release() end)
    end
    local MediaPlayer = luajava.bindClass("android.media.MediaPlayer")
    startup_sound_mp = luajava.new(MediaPlayer)
    startup_sound_mp.setDataSource("/sdcard/解说/Plugins/hi/hi.aac")
    startup_sound_mp.setOnCompletionListener(luajava.createProxy("android.media.MediaPlayer$OnCompletionListener", {
        onCompletion = function(mediaPlayer)
            pcall(function() 
                mediaPlayer.release() 
                startup_sound_mp = nil
            end)
        end
    }))
    startup_sound_mp.prepare()
    startup_sound_mp.start()
end)
-- STARTUP_SOUND_INJECTOR_END
local AlertDialog = luajava.bindClass("android.app.AlertDialog$Builder")
local File = luajava.bindClass("java.io.File")
local Toast = luajava.bindClass("android.widget.Toast")
local EditText = luajava.bindClass("android.widget.EditText")
local CharSequence = luajava.bindClass("java.lang.CharSequence")
local Context = luajava.bindClass("android.content.Context")
local ClipData = luajava.bindClass("android.content.ClipData")

-- Global Variables
local selected_audio = ""
local selected_ext_path = ""
local selected_ext_name = ""
local preview_mp = nil 
local current_sort_mode = "A-Z" -- Default sort mode

-- Helper to load sort mode from persistent file
local function loadSortMode()
    local io = require "io"
    local f = io.open("/sdcard/解说/Plugins/sound_injector_sort.txt", "r")
    if f then
        local mode = f:read("*l")
        if mode == "A-Z" or mode == "Z-A" or mode == "Newest" or mode == "Oldest" then
            current_sort_mode = mode
        end
        f:close()
    end
end

-- Helper to save sort mode to persistent file
local function saveSortMode()
    local io = require "io"
    local f = io.open("/sdcard/解说/Plugins/sound_injector_sort.txt", "w")
    if f then
        f:write(current_sort_mode)
        f:close()
    end
end

local favorites = {}
-- Helper to load favorites from persistent file
local function loadFavorites()
    favorites = {}
    local io = require "io"
    local f = io.open("/sdcard/解说/Plugins/sound_injector_favs.txt", "r")
    if f then
        for line in f:lines() do
            if line ~= "" then
                local path, name = line:match("^(.-)|||_|||(.*)$")
                if path and name then
                    table.insert(favorites, {path = path, name = name})
                else
                    table.insert(favorites, {path = line, name = line:match("[^/]+$") or line})
                end
            end
        end
        f:close()
    end
end

-- Helper to save favorites to persistent file
local function saveFavorites()
    local io = require "io"
    local f = io.open("/sdcard/解说/Plugins/sound_injector_favs.txt", "w")
    if f then
        for _, fav in ipairs(favorites) do
            f:write(fav.path .. "|||_|||" .. fav.name .. "\n")
        end
        f:close()
    end
end

-- Dummy listener to safely pass instead of 'nil'
local dummyListener = luajava.createProxy("android.content.DialogInterface$OnClickListener", {
    onClick = function(dialog, which) end
})

-- 1. Helper function for Native Android Clipboard
local function copyToClipboard(text)
    pcall(function()
        local clipboard = service.getSystemService(Context.CLIPBOARD_SERVICE)
        local clip = ClipData.newPlainText("InjectedCode", text)
        clipboard.setPrimaryClip(clip)
    end)
end

-- 2. Helper function to safely show dialogs from an Accessibility Service context
local function showServiceDialog(builder)
    local dialog = builder.create()
    local window = dialog.getWindow()
    if window then
        window.setType(2032) -- WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY
    end
    dialog.show()
end

-- Helper to check if a directory contains audio files
local function dirContainsAudio(dirObj, depth)
    if depth > 2 then return false end
    local list = dirObj.listFiles()
    if not list then return false end
    for i = 0, #list - 1 do
        local item = list[i]
        if item.isFile() then
            local name = item.getName():lower()
            if name:find("%.mp3$") or name:find("%.wav$") or name:find("%.ogg$") or name:find("%.m4a$") or name:find("%.aac$") then
                return true
            end
        elseif item.isDirectory() then
            if dirContainsAudio(item, depth + 1) then
                return true
            end
        end
    end
    return false
end

-- Helper to recursively scan ALL internal storage for audio files
local function scanAllStorageForAudios(dirObj, list_to_fill)
    local files = dirObj.listFiles()
    if not files then return end
    for i = 0, #files - 1 do
        local item = files[i]
        local name = item.getName()
        local uname = name:lower()
        if item.isDirectory() then
            if name ~= "Android" and not uname:find("recycle") and not uname:find("trash") and not uname:find("cache") then
                scanAllStorageForAudios(item, list_to_fill)
            end
        else
            if uname:find("%.mp3$") or uname:find("%.wav$") or uname:find("%.ogg$") or uname:find("%.m4a$") or uname:find("%.aac$") then
                table.insert(list_to_fill, {
                    name = name,
                    pure_name = name,
                    path = item.getAbsolutePath(),
                    time = item.lastModified()
                })
            end
        end
    end
end

-- Universal Sort Options Dialog
function showSortOptionsDialog(on_select_callback)
    local modes = {"A to Z", "Z to A", "Newest First", "Oldest First"}
    local modes_internal = {"A-Z", "Z-A", "Newest", "Oldest"}
    local array = luajava.newArray(CharSequence, #modes)
    for i = 1, #modes do array[i-1] = modes[i] end
    
    local builder = luajava.new(AlertDialog, service)
    builder.setTitle("Sort By")
    builder.setItems(array, luajava.createProxy("android.content.DialogInterface$OnClickListener", {
        onClick = function(dialog, which)
            current_sort_mode = modes_internal[which + 1]
            saveSortMode()
            on_select_callback()
        end
    }))
    builder.setNegativeButton("Back", luajava.createProxy("android.content.DialogInterface$OnClickListener", {
        onClick = function(dialog, which)
            if on_select_callback then on_select_callback() end
        end
    }))
    showServiceDialog(builder)
end

-- 3. Main Menu Dialog
function mainMenu()
    loadSortMode() 
    local items_table = {
        "Choose Audio File\n(Selected: " .. (selected_audio ~= "" and selected_audio:match("[^/]+$") or "None") .. ")",
        "Select Your Extension\n(Selected: " .. (selected_ext_name ~= "" and selected_ext_name or "None") .. ")",
        "Generate and Inject Code",
        "About"
    }
    
    local itemsArray = luajava.newArray(CharSequence, #items_table)
    for i = 1, #items_table do
        itemsArray[i-1] = items_table[i]
    end
    
    local builder = luajava.new(AlertDialog, service)
    builder.setTitle("Sound Startup Injector created by A brothers")
    
    local menuProxy = luajava.createProxy("android.content.DialogInterface$OnClickListener", {
        onClick = function(dialog, which)
            if which == 0 then
                chooseAudioDialog()
            elseif which == 1 then
                chooseExtensionDialog()
            elseif which == 2 then
                generateInjectedCode()
            elseif which == 3 then
                showAboutDialog()
            end
        end
    })
    
    builder.setItems(itemsArray, menuProxy)
    builder.setNegativeButton("Exit", dummyListener)
    showServiceDialog(builder)
end

-- 3b. About & Feedback Dialog Panel
function showAboutDialog()
    local builder = luajava.new(AlertDialog, service)
    builder.setTitle("Sound Startup Injector created by A brothers")
    builder.setMessage("This utility allows you to inject audio startups into your chosen extensions seamlessly.\n\nDeveloped by A brothers.")
    
    builder.setPositiveButton("Help & Feedback", luajava.createProxy("android.content.DialogInterface$OnClickListener", {
        onClick = function(dialog, which)
            pcall(function()
                local Intent = luajava.bindClass("android.content.Intent")
                local Uri = luajava.bindClass("android.net.Uri")
                local msg = "Hello, I need help or feedback regarding Sound Startup Injector created by A brothers"
                local url = "https://api.whatsapp.com/send?phone=923477583735&text=" .. msg:gsub(" ", "%%20")
                local intent = luajava.new(Intent, Intent.ACTION_VIEW)
                intent.setData(Uri.parse(url))
                intent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                service.startActivity(intent)
            end)
        end
    }))
    builder.setNegativeButton("Exit", dummyListener)
    showServiceDialog(builder)
end

-- 4. Audio Selection Main Access
function chooseAudioDialog()
    local menu_items = {
        "Browse Folders",
        "All Files",
        "Favorites"
    }
    local itemsArray = luajava.newArray(CharSequence, #menu_items)
    for i = 1, #menu_items do
        itemsArray[i-1] = menu_items[i]
    end
    
    local builder = luajava.new(AlertDialog, service)
    builder.setTitle("Choose Audio File")
    
    local proxy = luajava.createProxy("android.content.DialogInterface$OnClickListener", {
        onClick = function(dialog, which)
            if which == 0 then
                browseAudioFolder("/sdcard/", nil)
            elseif which == 1 then
                showAllFilesList(nil)
            elseif which == 2 then
                showFavoritesDialog()
            end
        end
    })
    builder.setItems(itemsArray, proxy)
    builder.setNegativeButton("Back", luajava.createProxy("android.content.DialogInterface$OnClickListener", {
        onClick = function(dialog, which) mainMenu() end
    }))
    showServiceDialog(builder)
end

-- 4a. Browse Folders View
function browseAudioFolder(current_path, search_query)
    local f = luajava.new(File, current_path)
    local list = f.listFiles()
    local items = {}
    
    if list then
        for i = 0, #list - 1 do
            local item = list[i]
            local name = item.getName()
            if item.isDirectory() then
                if dirContainsAudio(item, 1) then
                    if not search_query or name:lower():find(search_query:lower()) then
                        table.insert(items, {name = "[Folder] " .. name, path = item.getAbsolutePath(), is_dir = true, time = item.lastModified(), pure_name = name})
                    end
                end
            elseif item.isFile() then
                local uname = name:lower()
                if uname:find("%.mp3$") or uname:find("%.wav$") or uname:find("%.ogg$") or uname:find("%.m4a$") or uname:find("%.aac$") then
                    if not search_query or name:lower():find(search_query:lower()) then
                        table.insert(items, {name = name, path = item.getAbsolutePath(), is_dir = false, time = item.lastModified(), pure_name = name})
                    end
                end
            end
        end
    end
    
    table.sort(items, function(a, b)
        if current_sort_mode == "A-Z" then
            return a.pure_name:lower() < b.pure_name:lower()
        elseif current_sort_mode == "Z-A" then
            return a.pure_name:lower() > b.pure_name:lower()
        elseif current_sort_mode == "Newest" then
            return a.time > b.time
        elseif current_sort_mode == "Oldest" then
            return a.time < b.time
        end
        return a.pure_name:lower() < b.pure_name:lower()
    end)
    
    local display_names = {}
    table.insert(display_names, "Long Press to Add Favorite Audio")
    if search_query then
        table.insert(display_names, "Clear Search Filter")
    else
        table.insert(display_names, "Search Folder or File")
    end
    table.insert(display_names, "Sort By: " .. current_sort_mode)
    
    local has_parent = (current_path ~= "/sdcard/" and current_path ~= "/sdcard" and current_path ~= "/")
    if has_parent then
        table.insert(display_names, "Go Up (..)")
    end
    
    for _, item in ipairs(items) do
        table.insert(display_names, item.name)
    end
    
    local builder = luajava.new(AlertDialog, service)
    builder.setTitle("Browse Folders")
    
    local ListView = luajava.bindClass("android.widget.ListView")
    local ArrayAdapter = luajava.bindClass("android.widget.ArrayAdapter")
    local android_layout = luajava.bindClass("android.R$layout")
    
    local namesArray = luajava.newArray(CharSequence, #display_names)
    for i = 1, #display_names do namesArray[i-1] = display_names[i] end
    
    local adapter = luajava.new(ArrayAdapter, service, android_layout.simple_list_item_1, namesArray)
    local listView = luajava.new(ListView, service)
    listView.setAdapter(adapter)
    builder.setView(listView)
    
    builder.setNegativeButton("Back to Menu", luajava.createProxy("android.content.DialogInterface$OnClickListener", {
        onClick = function(dialog, which) chooseAudioDialog() end
    }))
    
    local dialog = builder.create()
    local window = dialog.getWindow()
    if window then window.setType(2032) end
    
    listView.setOnItemClickListener(luajava.createProxy("android.widget.AdapterView$OnItemClickListener", {
        onItemClick = function(parent, view, position, id)
            local offset = 3
            if has_parent then offset = 4 end
            
            if position == 0 then
                -- Heading item, do nothing
            elseif position == 1 then
                dialog.dismiss()
                if search_query then
                    browseAudioFolder(current_path, nil)
                else
                    local sb = luajava.new(AlertDialog, service)
                    sb.setTitle("Search")
                    local input = luajava.new(EditText, service)
                    sb.setView(input)
                    sb.setPositiveButton("OK", luajava.createProxy("android.content.DialogInterface$OnClickListener", {
                        onClick = function(d, w)
                            browseAudioFolder(current_path, tostring(input.getText()))
                        end
                    }))
                    sb.setNegativeButton("Back", luajava.createProxy("android.content.DialogInterface$OnClickListener", {
                        onClick = function(d, w) browseAudioFolder(current_path, search_query) end
                    }))
                    showServiceDialog(sb)
                end
            elseif position == 2 then
                dialog.dismiss()
                showSortOptionsDialog(function() browseAudioFolder(current_path, search_query) end)
            elseif has_parent and position == 3 then
                dialog.dismiss()
                browseAudioFolder(f.getParent(), nil)
            else
                local item_idx = position - offset + 1
                local target = items[item_idx]
                if target then
                    dialog.dismiss()
                    if target.is_dir then
                        browseAudioFolder(target.path, nil)
                    else
                        audioOptionsDialog(target.path, function() browseAudioFolder(current_path, search_query) end)
                    end
                end
            end
        end
    }))
    
    listView.setOnItemLongClickListener(luajava.createProxy("android.widget.AdapterView$OnItemLongClickListener", {
        onItemLongClick = function(parent, view, position, id)
            local offset = 3
            if has_parent then offset = 4 end
            if position >= offset then
                local item_idx = position - offset + 1
                local target = items[item_idx]
                if target and not target.is_dir then
                    loadFavorites()
                    local exists = false
                    for _, fav in ipairs(favorites) do
                        if fav.path == target.path then exists = true break end
                    end
                    if not exists then
                        table.insert(favorites, {path = target.path, name = target.pure_name})
                        saveFavorites()
                        pcall(function() service.speak("Added to favorites") end)
                    else
                        pcall(function() service.speak("Already in favorites") end)
                    end
                end
            end
            return true 
        end
    }))
    
    dialog.show()
end

-- 4b. Audio Play Preview and Select Dialog (Fixed Focus and Anti-Window Jump Logic)
function audioOptionsDialog(audio_path, back_callback)
    local is_playing = false
    pcall(function()
        if preview_mp and preview_mp.isPlaying() then
            is_playing = true
        end
    end)
    
    local play_toggle_text = is_playing and "Pause Audio" or "Play Audio"
    local options_table = {
        "Choose Your Audio",
        play_toggle_text,
        "Select Your Audio"
    }
    
    local builder = luajava.new(AlertDialog, service)
    builder.setTitle(audio_path:match("[^/]+$") or audio_path)
    
    local ListView = luajava.bindClass("android.widget.ListView")
    local ArrayAdapter = luajava.bindClass("android.widget.ArrayAdapter")
    local android_layout = luajava.bindClass("android.R$layout")
    
    local array = luajava.newArray(CharSequence, #options_table)
    for i = 1, #options_table do array[i-1] = options_table[i] end
    
    local adapter = luajava.new(ArrayAdapter, service, android_layout.simple_list_item_1, array)
    local listView = luajava.new(ListView, service)
    listView.setAdapter(adapter)
    builder.setView(listView)
    
    builder.setNegativeButton("Back", luajava.createProxy("android.content.DialogInterface$OnClickListener", {
        onClick = function(dialog, which)
            if preview_mp then
                pcall(function() preview_mp.release() end)
                preview_mp = nil
            end
            dialog.dismiss()
            if back_callback then back_callback() end
        end
    }))
    
    local dialog = builder.create()
    local window = dialog.getWindow()
    if window then window.setType(2032) end
    
    listView.setOnItemClickListener(luajava.createProxy("android.widget.AdapterView$OnItemClickListener", {
        onItemClick = function(parent, view, position, id)
            if position == 0 then 
                if preview_mp then
                    pcall(function() preview_mp.release() end)
                    preview_mp = nil
                end
                dialog.dismiss()
                chooseAudioDialog()
                
            elseif position == 1 then 
                if is_playing then
                    pcall(function()
                        preview_mp.pause()
                        service.speak("Paused")
                    end)
                    is_playing = false
                else
                    pcall(function()
                        if preview_mp then
                            preview_mp.start()
                        else
                            local MediaPlayer = luajava.bindClass("android.media.MediaPlayer")
                            preview_mp = luajava.new(MediaPlayer)
                            preview_mp.setDataSource(audio_path)
                            preview_mp.setOnCompletionListener(luajava.createProxy("android.media.MediaPlayer$OnCompletionListener", {
                                onCompletion = function(mp)
                                    pcall(function()
                                        mp.release()
                                        preview_mp = nil
                                        is_playing = false
                                        local itemView = listView.getChildAt(1)
                                        if itemView then
                                            itemView.setText("Play Audio")
                                        end
                                    end)
                                end
                            }))
                            preview_mp.prepare()
                            preview_mp.start()
                        end
                        service.speak("Playing preview")
                    end)
                    is_playing = true
                end
                
                local updated_toggle_text = is_playing and "Pause Audio" or "Play Audio"
                pcall(function()
                    local itemView = listView.getChildAt(1)
                    if itemView then
                        itemView.setText(updated_toggle_text)
                    end
                end)
                
            elseif position == 2 then 
                if preview_mp then
                    pcall(function() preview_mp.release() end)
                    preview_mp = nil
                end
                selected_audio = audio_path
                pcall(function() service.speak("Audio selected") end)
                dialog.dismiss()
                mainMenu()
            end
        end
    }))
    
    dialog.show()
end

-- 4c. All Files View
function showAllFilesList(search_query)
    local items = {}
    local storageDir = luajava.new(File, "/sdcard/")
    
    pcall(function() scanAllStorageForAudios(storageDir, items) end)
    
    if search_query then
        local filtered = {}
        for _, item in ipairs(items) do
            if item.pure_name:lower():find(search_query:lower()) then
                table.insert(filtered, item)
            end
        end
        items = filtered
    end
    
    table.sort(items, function(a, b)
        if current_sort_mode == "A-Z" then
            return a.pure_name:lower() < b.pure_name:lower()
        elseif current_sort_mode == "Z-A" then
            return a.pure_name:lower() > b.pure_name:lower()
        elseif current_sort_mode == "Newest" then
            return a.time > b.time
        elseif current_sort_mode == "Oldest" then
            return a.time < b.time
        end
        return a.pure_name:lower() < b.pure_name:lower()
    end)
    
    local display_names = {}
    table.insert(display_names, "Long Press to Add Favorite Audio")
    if search_query then
        table.insert(display_names, "Clear Search Filter")
    else
        table.insert(display_names, "Search File")
    end
    table.insert(display_names, "Sort By: " .. current_sort_mode)
    
    for _, item in ipairs(items) do
        table.insert(display_names, item.name)
    end
    
    local builder = luajava.new(AlertDialog, service)
    builder.setTitle("All Files")
    
    local ListView = luajava.bindClass("android.widget.ListView")
    local ArrayAdapter = luajava.bindClass("android.widget.ArrayAdapter")
    local android_layout = luajava.bindClass("android.R$layout")
    
    local namesArray = luajava.newArray(CharSequence, #display_names)
    for i = 1, #display_names do namesArray[i-1] = display_names[i] end
    
    local adapter = luajava.new(ArrayAdapter, service, android_layout.simple_list_item_1, namesArray)
    local listView = luajava.new(ListView, service)
    listView.setAdapter(adapter)
    builder.setView(listView)
    
    builder.setNegativeButton("Back", luajava.createProxy("android.content.DialogInterface$OnClickListener", {
        onClick = function(dialog, which) chooseAudioDialog() end
    }))
    
    local dialog = builder.create()
    local window = dialog.getWindow()
    if window then window.setType(2032) end
    
    listView.setOnItemClickListener(luajava.createProxy("android.widget.AdapterView$OnItemClickListener", {
        onItemClick = function(parent, view, position, id)
            if position == 0 then
                -- Heading item, do nothing
            elseif position == 1 then
                dialog.dismiss()
                if search_query then
                    showAllFilesList(nil)
                else
                    local sb = luajava.new(AlertDialog, service)
                    sb.setTitle("Search")
                    local input = luajava.new(EditText, service)
                    sb.setView(input)
                    sb.setPositiveButton("OK", luajava.createProxy("android.content.DialogInterface$OnClickListener", {
                        onClick = function(d, w)
                            showAllFilesList(tostring(input.getText()))
                        end
                    }))
                    sb.setNegativeButton("Back", luajava.createProxy("android.content.DialogInterface$OnClickListener", {
                        onClick = function(d, w) showAllFilesList(search_query) end
                    }))
                    showServiceDialog(sb)
                end
            elseif position == 2 then
                dialog.dismiss()
                showSortOptionsDialog(function() showAllFilesList(search_query) end)
            else
                local target = items[position - 2]
                if target then
                    dialog.dismiss()
                    audioOptionsDialog(target.path, function() showAllFilesList(search_query) end)
                end
            end
        end
    }))
    
    listView.setOnItemLongClickListener(luajava.createProxy("android.widget.AdapterView$OnItemLongClickListener", {
        onItemLongClick = function(parent, view, position, id)
            if position >= 3 then
                local target = items[position - 2]
                if target then
                    loadFavorites()
                    local exists = false
                    for _, fav in ipairs(favorites) do
                        if fav.path == target.path then exists = true break end
                    end
                    if not exists then
                        table.insert(favorites, {path = target.path, name = target.pure_name})
                        saveFavorites()
                        pcall(function() service.speak("Added to favorites") end)
                    else
                        pcall(function() service.speak("Already in favorites") end)
                    end
                end
            end
            return true
        end
    }))
    
    dialog.show()
end

-- 4d. Favorites View Panel
function showFavoritesDialog()
    loadFavorites()
    
    local display_names = {}
    table.insert(display_names, "Favorites")
    table.insert(display_names, "Long Press to Remove Favorite, Double Tap to Open Player Options")
    
    if #favorites == 0 then
        table.insert(display_names, "(No Favorites Added Yet)")
    else
        for _, fav in ipairs(favorites) do
            table.insert(display_names, fav.name)
        end
    end
    
    local builder = luajava.new(AlertDialog, service)
    builder.setTitle("Favorites")
    
    local ListView = luajava.bindClass("android.widget.ListView")
    local ArrayAdapter = luajava.bindClass("android.widget.ArrayAdapter")
    local android_layout = luajava.bindClass("android.R$layout")
    
    local namesArray = luajava.newArray(CharSequence, #display_names)
    for i = 1, #display_names do namesArray[i-1] = display_names[i] end
    
    local adapter = luajava.new(ArrayAdapter, service, android_layout.simple_list_item_1, namesArray)
    local listView = luajava.new(ListView, service)
    listView.setAdapter(adapter)
    builder.setView(listView)
    
    builder.setNegativeButton("Back", luajava.createProxy("android.content.DialogInterface$OnClickListener", {
        onClick = function(dialog, which) chooseAudioDialog() end
    }))
    
    local dialog = builder.create()
    local window = dialog.getWindow()
    if window then window.setType(2032) end
    
    listView.setOnItemClickListener(luajava.createProxy("android.widget.AdapterView$OnItemClickListener", {
        onItemClick = function(parent, view, position, id)
            if position >= 2 and #favorites > 0 then
                local target = favorites[position - 1]
                if target then
                    dialog.dismiss()
                    audioOptionsDialog(target.path, function() showFavoritesDialog() end)
                end
            end
        end
    }))
    
    listView.setOnItemLongClickListener(luajava.createProxy("android.widget.AdapterView$OnItemLongClickListener", {
        onItemLongClick = function(parent, view, position, id)
            if position >= 2 and #favorites > 0 then
                local item_idx = position - 1
                local target = favorites[item_idx]
                if target then
                    pcall(function() service.speak("Removed from favorites") end)
                    table.remove(favorites, item_idx)
                    saveFavorites()
                    dialog.dismiss()
                    showFavoritesDialog()
                end
            end
            return true
        end
    }))
    
    dialog.show()
end

-- 6. Extension Selection Dialog
function chooseExtensionDialog(filter_query)
    local plugin_dir = "/sdcard/解说/Plugins/"
    local f = luajava.new(File, plugin_dir)
    local list = f.listFiles()
    local ext_pairs = {}
    
    if list then
        for i = 0, #list - 1 do
            if list[i].isDirectory() then
                local name = list[i].getName()
                if not filter_query or name:lower():find(filter_query:lower()) then
                    table.insert(ext_pairs, {name = name, path = list[i].getAbsolutePath()})
                end
            end
        end
    end
    
    table.sort(ext_pairs, function(a, b) return a.name:lower() < b.name:lower() end)
    
    local display_names = {}
    local display_paths = {}
    
    if filter_query then
        table.insert(display_names, "Clear Search Filter")
    else
        table.insert(display_names, "Search Extension")
    end
    
    for _, pair in ipairs(ext_pairs) do
        table.insert(display_names, pair.name)
        table.insert(display_paths, pair.path)
    end
    
    local extArray = luajava.newArray(CharSequence, #display_names)
    for i = 1, #display_names do
        extArray[i-1] = display_names[i]
    end
    
    local builder = luajava.new(AlertDialog, service)
    builder.setTitle("Select Target Extension")
    
    local extProxy = luajava.createProxy("android.content.DialogInterface$OnClickListener", {
        onClick = function(dialog, which)
            if which == 0 then
                if filter_query then
                    chooseExtensionDialog(nil)
                else
                    local search_builder = luajava.new(AlertDialog, service)
                    search_builder.setTitle("Enter Extension Name")
                    local input = luajava.new(EditText, service)
                    search_builder.setView(input)
                    search_builder.setPositiveButton("Search", luajava.createProxy("android.content.DialogInterface$OnClickListener", {
                        onClick = function(d, w)
                            local q = tostring(input.getText())
                            chooseExtensionDialog(q)
                        end
                    }))
                    search_builder.setNegativeButton("Back", luajava.createProxy("android.content.DialogInterface$OnClickListener", {
                        onClick = function(d, w) chooseExtensionDialog(filter_query) end
                    }))
                    showServiceDialog(search_builder)
                end
            else
                local actual_idx = filter_query and which or which
                selected_ext_name = display_names[actual_idx + 1]
                selected_ext_path = display_paths[actual_idx]
                pcall(function() service.speak("Selected extension " .. selected_ext_name) end)
                mainMenu()
            end
        end
    })
    
    builder.setItems(extArray, extProxy)
    builder.setNegativeButton("Back", luajava.createProxy("android.content.DialogInterface$OnClickListener", {
        onClick = function(dialog, which) mainMenu() end
    }))
    showServiceDialog(builder)
end

-- 7. Dialog to display the generated code with native copy
function showCodeDisplayDialog(generated_code)
    local builder = luajava.new(AlertDialog, service)
    builder.setTitle("Generated Injected Code")
    
    local codeInput = luajava.new(EditText, service)
    codeInput.setText(generated_code)
    builder.setView(codeInput)
    
    local copyProxy = luajava.createProxy("android.content.DialogInterface$OnClickListener", {
        onClick = function(dialog, which)
            copyToClipboard(generated_code)
            pcall(function() service.speak("Code copied") end)
            
            pcall(function()
                local toastObj = Toast.makeText(service, "Code saved and copied to clipboard!", 1)
                toastObj.show()
            end)
            
            mainMenu()
        end
    })
    builder.setPositiveButton("Copy Code", copyProxy)
    
    local closeProxy = luajava.createProxy("android.content.DialogInterface$OnClickListener", {
        onClick = function(dialog, which) mainMenu() end
    })
    builder.setNegativeButton("Close", closeProxy)
    
    showServiceDialog(builder)
end

-- 8. Code Generation and Injection Logic (Smart Insertion After "require" for Git Compatibility)
function generateInjectedCode()
    if selected_audio == "" or selected_ext_path == "" then
        pcall(function() service.speak("Please select audio and extension first.") end)
        mainMenu()
        return
    end
    
    local main_lua_path = selected_ext_path .. "/main.lua"
    local f = luajava.new(File, main_lua_path)
    if not f.exists() then
        pcall(function() service.speak("main.lua not found.") end)
        mainMenu()
        return
    end
    
    local raw_ext = selected_audio:match("%.([^%.]+)$") or "mp3"
    local ext = raw_ext:lower()
    local target_file_name = selected_ext_name .. "." .. ext
    local target_file_path = selected_ext_path .. "/" .. target_file_name
    
    local target_dir_obj = luajava.new(File, selected_ext_path)
    local dir_files = target_dir_obj.listFiles()
    if dir_files then
        for i = 0, #dir_files - 1 do
            local item = dir_files[i]
            if item.isFile() then
                local item_name = item.getName():lower()
                if item_name:find("%.mp3$") or item_name:find("%.wav$") or item_name:find("%.ogg$") or item_name:find("%.m4a$") or item_name:find("%.aac$") then
                    item.delete()
                end
            end
        end
    end
    
    local io = require "io"
    local success_copy, copy_err = pcall(function()
        local infile = io.open(selected_audio, "rb")
        if not infile then error("Source audio readable issue") end
        local data = infile:read("*all")
        infile:close()
        
        local outfile = io.open(target_file_path, "wb")
        if not outfile then error("Destination path write issue") end
        outfile:write(data)
        outfile:close()
    end)
    
    if not success_copy then
        pcall(function() service.speak("Failed to copy file: " .. tostring(copy_err)) end)
        mainMenu()
        return
    end
    
    local lines = {}
    local skip = false
    local file = io.open(main_lua_path, "r")
    if not file then
        pcall(function() service.speak("Failed to read code.") end)
        return
    end
    
    for line in file:lines() do
        if line:find("STARTUP_SOUND_" .. "INJECTOR_START", 1, true) or line:find("[Startup Sound " .. "Injector Code Start]", 1, true) then
            skip = true
        end
        
        if not skip then
            table.insert(lines, line)
        end
        
        if line:find("STARTUP_SOUND_" .. "INJECTOR_END", 1, true) or line:find("[Startup Sound " .. "Injector Code End]", 1, true) then
            skip = false
        end
    end
    file:close()
    
    -- نیا کلین بلاک تیار کریں گے
    local injected_logic_block = "-- STARTUP_SOUND_" .. "INJECTOR_START\n"
    .. "pcall(function()\n"
    .. "    if startup_sound_mp ~= nil then\n"
    .. "        pcall(function() startup_sound_mp.release() end)\n"
    .. "    end\n"
    .. "    local MediaPlayer = luajava.bindClass(\"android.media.MediaPlayer\")\n"
    .. "    startup_sound_mp = luajava.new(MediaPlayer)\n"
    .. "    startup_sound_mp.setDataSource(\"" .. target_file_path .. "\")\n"
    .. "    startup_sound_mp.setOnCompletionListener(luajava.createProxy(\"android.media.MediaPlayer$OnCompletionListener\", {\n"
    .. "        onCompletion = function(mediaPlayer)\n"
    .. "            pcall(function() \n"
    .. "                mediaPlayer.release() \n"
    .. "                startup_sound_mp = nil\n"
    .. "            end)\n"
    .. "        end\n"
    .. "    }))\n"
    .. "    startup_sound_mp.prepare()\n"
    .. "    startup_sound_mp.start()\n"
    .. "end)\n" -- [فکسڈ]: اب یہاں ڈبل ڈاٹ اور بریکٹ اسٹرنگ کے اندر بالکل درست کام کر رہے ہیں
    .. "-- STARTUP_SOUND_" .. "INJECTOR_END"

    -- سمارٹ انجیکشن فکس
    local final_lines = {}
    local injected = false
    for _, line in ipairs(lines) do
        table.insert(final_lines, line)
        if not injected and line:find("require", 1, true) and line:find("import", 1, true) then
            table.insert(final_lines, injected_logic_block)
            injected = true
        end
    end
    
    if not injected then
        table.insert(final_lines, 1, injected_logic_block)
    end
    
    local final_output_code = table.concat(final_lines, "\n")

    local backup_path = selected_ext_path .. "/main.lua.bak"
    local backup_file = io.open(backup_path, "w")
    if backup_file then
        backup_file:write(table.concat(lines, "\n"))
        backup_file:close()
    end
    
    local out_file = io.open(main_lua_path, "w")
    if out_file then
        out_file:write(final_output_code)
        out_file:close()
        pcall(function() service.speak("Audio copied and code injected successfully") end)
        
        showCodeDisplayDialog(final_output_code)
    else
        pcall(function() service.speak("Failed to write code.") end)
    end
end

-- Start the script interface
mainMenu()