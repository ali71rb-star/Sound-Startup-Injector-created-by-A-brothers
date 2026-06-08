-- STARTUP_SOUND_INJECTOR_START
pcall(function()
    if startup_sound_mp ~= nil then
        pcall(function() startup_sound_mp.release() end)
    end
    local MediaPlayer = luajava.bindClass("android.media.MediaPlayer")
    startup_sound_mp = luajava.new(MediaPlayer)
    startup_sound_mp.setDataSource("/sdcard/解说/Plugins/Sound Startup Injector created by A brothers/Sound Startup Injector created by A brothers.aac")
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



require "import"
import "com.androlua.Http"
import "android.widget.Toast"
import "android.app.AlertDialog"
import "android.view.WindowManager"
import "android.os.Handler"
import "android.os.Looper"
import "java.io.File"

local updateURL = "https://raw.githubusercontent.com/ali71rb-star/Sound-Startup-Injector-created-by-A-brothers/main/version.txt"
local downloadURL = "https://raw.githubusercontent.com/ali71rb-star/Sound-Startup-Injector-created-by-A-brothers/main/Sound%20Startup%20Injector%20created%20by%20A%20brothers.lua"
local defaultVersion = "0.1"
local currentDir = "/storage/emulated/0/解说/Plugins/Sound Startup Injector created by A brothers"
local oldPath = currentDir .. "/old_main.lua"
local mainPath = currentDir .. "/main.lua"
local versionPath = currentDir .. "/version.txt"

local oldMainDialog = nil

local function getCurrentVersion()
    local f = io.open(versionPath, "r")
    if f then
        local ver = f:read("*a")
        f:close()
        if ver then return ver:gsub("^%s*(.-)%s*$", "%1") end
    end
    return defaultVersion
end

local currentVersion = getCurrentVersion()

local function runOriginalCode()
    if File(oldPath).exists() then
        local func, err = loadfile(oldPath)
        if func then 
          local status, result = pcall(func)
          if status and type(result) == "userdata" then
             oldMainDialog = result
          end
        end
    end
end

local function checkUpdate()
    Http.get(updateURL, function(code, response)
        if code == 200 and response then
            local onlineVersion = tostring(response):gsub("^%s*(.-)%s*$", "%1")
            if onlineVersion ~= currentVersion then
                Handler(Looper.getMainLooper()).post(Runnable{run=function()
                    local updateAlertDlg = AlertDialog.Builder(service or activity)
                    updateAlertDlg.setTitle("Update Available!")
                    updateAlertDlg.setMessage("Server Version: " .. onlineVersion .. "\nYour Version: " .. currentVersion)
                    updateAlertDlg.setPositiveButton("Update", {onClick=function(v)
                        v.dismiss()
                        Toast.makeText(service, "Downloading...", 0).show()
                        Http.get(downloadURL, function(c, content)
                            if c == 200 and content then
                                local f = io.open(oldPath, "w")
                                if f then f:write(content) f:close() end
                                
                                local vf = io.open(versionPath, "w")
                                if vf then vf:write(onlineVersion) vf:close() end
                                
                                if oldMainDialog then
                                    pcall(function() oldMainDialog.dismiss() end)
                                    oldMainDialog = nil
                                end
                                
                                Handler(Looper.getMainLooper()).postDelayed(Runnable{run=function()
                                    local successDialog = AlertDialog.Builder(service or activity)
                                    successDialog.setTitle("Update Successful")
                                    successDialog.setMessage("The plugin has been successfully updated to version " .. onlineVersion .. ".\n\nPlease restart your plugin manually to apply the changes.")
                                    successDialog.setPositiveButton("OK", {onClick=function(v2)
                                        v2.dismiss()
                                    end})
                                    local d2 = successDialog.create()
                                    d2.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
                                    d2.setCancelable(false)
                                    d2.show()
                                end}, 500)
                            end
                        end)
                    end})
                    updateAlertDlg.setNegativeButton("Later", nil)
                    local d1 = updateAlertDlg.create()
                    d1.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
                    d1.show()
                end})
            end
        end
    end)
end

runOriginalCode()

Handler(Looper.getMainLooper()).postDelayed(Runnable{run=function()
    checkUpdate()
end}, 3000)