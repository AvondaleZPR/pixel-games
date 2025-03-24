--[[
    Название: Название механики
    Автор: Avondale, дискорд - avonda
    Описание механики: в общих словах, что происходит в механике
    Идеи по доработке: то, что может улучшить игру, но не было реализовано здесь
]]
math.randomseed(os.time())
require("avonlib")

local CLog = require("log")
local CInspect = require("inspect")
local CHelp = require("help")
local CJson = require("json")
local CTime = require("time")
local CAudio = require("audio")
local CColors = require("colors")

local tGame = {
    Cols = 24,
    Rows = 15, 
    Buttons = {}, 
}
local tConfig = {}

-- стейты или этапы игры
local GAMESTATE_SETUP = 1
local GAMESTATE_GAME = 2
local GAMESTATE_POSTGAME = 3
local GAMESTATE_FINISH = 4

local bGamePaused = false
local iGameState = GAMESTATE_SETUP
local iPrevTickTime = 0

local tGameStats = {
    StageLeftDuration = 0, 
    StageTotalDuration = 0, 
    CurrentStars = 0,
    TotalStars = 0,
    CurrentLives = 0,
    TotalLives = 0,
    Players = { -- максимум 6 игроков
        { Score = 0, Lives = 0, Color = CColors.NONE },
        { Score = 0, Lives = 0, Color = CColors.NONE },
        { Score = 0, Lives = 0, Color = CColors.NONE },
        { Score = 0, Lives = 0, Color = CColors.NONE },
        { Score = 0, Lives = 0, Color = CColors.NONE },
        { Score = 0, Lives = 0, Color = CColors.NONE },
    },
    TargetScore = 1,
    StageNum = 1,
    TotalStages = 3,
    TargetColor = CColors.NONE,
}

local tGameResults = {
    Won = false,
    AfterDelay = false,
    PlayersCount = 0,
    Score = 0,
    Color = CColors.NONE,
}

local tFloor = {} 
local tButtons = {}

local tFloorStruct = { 
    iColor = CColors.NONE,
    iBright = CColors.BRIGHT0,
    bClick = false,
    bDefect = false,
    iWeight = 0,
}
local tButtonStruct = { 
    bClick = false,
    bDefect = false,
}

local tPlayerInGame = {}

function StartGame(gameJson, gameConfigJson)
    tGame = CJson.decode(gameJson)
    tConfig = CJson.decode(gameConfigJson)

    for iX = 1, tGame.Cols do
        tFloor[iX] = {}    
        for iY = 1, tGame.Rows do
            tFloor[iX][iY] = CHelp.ShallowCopy(tFloorStruct) 
        end
    end

    for _, iId in pairs(tGame.Buttons) do
        tButtons[iId] = CHelp.ShallowCopy(tButtonStruct)
    end

    for iPlayerID = 1, #tGame.StartPositions do
        tGame.StartPositions[iPlayerID].Color = tonumber(tGame.StartPositions[iPlayerID].Color)
    end    

    tGameStats.TotalStages = tConfig.RoundCount
end

function NextTick()
    if iGameState == GAMESTATE_SETUP then
        GameSetupTick()
    end

    if iGameState == GAMESTATE_GAME then
        GameTick()
    end

    if iGameState == GAMESTATE_POSTGAME then
        PostGameTick()

        if not tGameResults.AfterDelay then
            tGameResults.AfterDelay = true
            return tGameResults
        end
    end

    if iGameState == GAMESTATE_FINISH then
        tGameResults.AfterDelay = false
        return tGameResults
    end     

    AL.CountTimers((CTime.unix() - iPrevTickTime) * 1000)
    iPrevTickTime = CTime.unix()
end

function GameSetupTick()
    SetGlobalColorBright(CColors.NONE, CColors.BRIGHT0)
    CPaint.BG()

    local iPlayersReady = 0
    for iPlayerID = 1, #tGame.StartPositions do
        local iBright = tConfig.Bright

        if CheckPositionClick(tGame.StartPositions[iPlayerID], tGame.StartPositionSize, tGame.StartPositionSize) or (CGameMode.bCountDownStarted and tPlayerInGame[iPlayerID]) then
            tPlayerInGame[iPlayerID] = true
            iPlayersReady = iPlayersReady + 1
            tGameStats.Players[iPlayerID].Color = tGame.StartPositions[iPlayerID].Color
        else
            tPlayerInGame[iPlayerID] = false
            iBright = iBright-2
            tGameStats.Players[iPlayerID].Color = CColors.NONE
        end

        CPaint.PlayerZone(iPlayerID, iBright)
    end

    if iPlayersReady > 1 and not CGameMode.bCountDownStarted then
        CGameMode.StartCountDown(10)
    end
end

function GameTick()
    CPaint.BG()

    for iPlayerID = 1, #tGame.StartPositions do
        if tPlayerInGame[iPlayerID] then
            local iBright = tConfig.Bright-2
            if CGameMode.iPlayerIDToMove == iPlayerID and CGameMode.bPlayerCanMove then
                iBright = tConfig.Bright
            end
            CPaint.PlayerZone(iPlayerID, iBright)
        end
    end

    CPaint.Crosshair()
end

function PostGameTick()
    
end

function RangeFloor(setPixel, setButton)
    for iX = 1, tGame.Cols do
        for iY = 1, tGame.Rows do
            setPixel(iX , iY, tFloor[iX][iY].iColor, tFloor[iX][iY].iBright)
        end
    end

    for i, tButton in pairs(tButtons) do
        setButton(i, tButton.iColor, tButton.iBright)
    end
end

function SwitchStage()
    
end

--GAMEMODE
CGameMode = {}
CGameMode.iCountdown = 0
CGameMode.iPlayerIDToMove = 0
CGameMode.bCountDownStarted = false
CGameMode.iCrosshairX = 0
CGameMode.iCrosshairY = 0
CGameMode.iCrosshairVel = 1
CGameMode.bPlayerCanMove = false
CGameMode.iWinnerID = 0

CGameMode.StartCountDown = function(iCountDownTime)
    CGameMode.iCountdown = iCountDownTime
    CGameMode.bCountDownStarted = true

    AL.NewTimer(1000, function()
        CAudio.PlaySyncFromScratch("")
        tGameStats.StageLeftDuration = CGameMode.iCountdown

        if CGameMode.iCountdown <= 0 then
            CGameMode.StartGame()
            
            return nil
        else
            CAudio.PlayLeftAudio(CGameMode.iCountdown)
            CGameMode.iCountdown = CGameMode.iCountdown - 1

            return 1000
        end
    end)
end

CGameMode.StartGame = function()
    CAudio.PlaySync(CAudio.START_GAME)
    CAudio.PlayRandomBackground()
    iGameState = GAMESTATE_GAME 

    CGameMode.NextPlayerMove()
end

CGameMode.EndGame = function()
    CAudio.StopBackground()

    local iMaxScore = -999

    for i = 1, #tGame.StartPositions do
        if tGameStats.Players[i].Score > iMaxScore then
            CGameMode.iWinnerID = i
            iMaxScore = tGameStats.Players[i].Score
            tGameResults.Score = tGameStats.Players[i].Score
        end
    end

    iGameState = GAMESTATE_POSTGAME  

    CAudio.PlaySyncFromScratch("")
    CAudio.PlaySyncColorSound(tGame.StartPositions[CGameMode.iWinnerID].Color)
    CAudio.PlaySync(CAudio.VICTORY)

    tGameResults.Won = true
    tGameResults.Color = tGame.StartPositions[CGameMode.iWinnerID].Color

    AL.NewTimer(10000, function()
        iGameState = GAMESTATE_FINISH
    end)  

    SetGlobalColorBright(tGameStats.Players[CGameMode.iWinnerID].Color, tConfig.Bright) 
end

CGameMode.NextPlayerMove = function()
    CGameMode.iCrosshairX = tGame.CenterX
    CGameMode.iCrosshairY = 1
    CGameMode.iCrosshairVel = 1
    CGameMode.bPlayerCanMove = false

    CGameMode.FindNextPlayerToMove()
end

CGameMode.FindNextPlayerToMove = function()
    repeat CGameMode.iPlayerIDToMove = CGameMode.iPlayerIDToMove + 1; if CGameMode.iPlayerIDToMove > #tGame.StartPositions then CGameMode.iPlayerIDToMove = 1; tGameStats.StageNum = tGameStats.StageNum+1 end
    until tPlayerInGame[CGameMode.iPlayerIDToMove]

    if tGameStats.StageNum <= tGameStats.TotalStages then
        CAudio.PlaySyncColorSound(tGame.StartPositions[CGameMode.iPlayerIDToMove].Color)
        tGameStats.TargetColor = tGame.StartPositions[CGameMode.iPlayerIDToMove].Color
        CGameMode.WaitForPlayerMove(true)
    else
        tGameStats.StageNum = tGameStats.StageNum-1
        CGameMode.EndGame()
    end
end

CGameMode.WaitForPlayerMove = function(bYAxis)
    AL.NewTimer(1500, function()
        CGameMode.bPlayerCanMove = true
        if CheckPositionClick(tGame.StartPositions[CGameMode.iPlayerIDToMove], tGame.StartPositionSize, tGame.StartPositionSize) then
            CGameMode.PlayerHit(bYAxis)
            CGameMode.bPlayerCanMove = false
            return nil;
        else
            if bYAxis then
                CGameMode.iCrosshairY = CGameMode.iCrosshairY + CGameMode.iCrosshairVel
                if CGameMode.iCrosshairY == 1 or CGameMode.iCrosshairY == tGame.Rows then 
                    CGameMode.iCrosshairVel = -CGameMode.iCrosshairVel
                end
            else
                CGameMode.iCrosshairX = CGameMode.iCrosshairX + CGameMode.iCrosshairVel
                if CGameMode.iCrosshairX == 1 or CGameMode.iCrosshairX == tGame.Cols then 
                    CGameMode.iCrosshairVel = -CGameMode.iCrosshairVel
                end
            end

            return 100;
        end
    end)
end

CGameMode.PlayerHit = function(bYAxis)
    if bYAxis then
        AL.NewTimer(1000, function()
            CGameMode.iCrosshairX = 1
            CGameMode.iCrosshairVel = 1
            CGameMode.WaitForPlayerMove(false)
        end)
    else
        CGameMode.RewardPlayerForHit()

        AL.NewTimer(3000, function()
            CGameMode.NextPlayerMove()
        end)
    end
end

CGameMode.RewardPlayerForHit = function()
    local iXDiff = math.abs(tGame.CenterX - CGameMode.iCrosshairX)
    local iYDiff = math.abs(tGame.CenterY - CGameMode.iCrosshairY)
    local iScore = (tGame.Cols-iXDiff*3) + (tGame.Rows-iYDiff*3)
    if iScore < 0 then iScore = 0 end
    if iXDiff < 3 and iYDiff < 3 then iScore = iScore*2 end
    if iXDiff == 0 and iYDiff == 0 then iScore = iScore*2 end

    CLog.print(iXDiff.." "..iYDiff.." "..iScore)

    tGameStats.Players[CGameMode.iPlayerIDToMove].Score = tGameStats.Players[CGameMode.iPlayerIDToMove].Score + iScore
    if tGameStats.Players[CGameMode.iPlayerIDToMove].Score > tGameStats.TargetScore then
        tGameStats.TargetScore = tGameStats.Players[CGameMode.iPlayerIDToMove].Score
    end
end
--//

--PAINT
CPaint = {}
CPaint.BG = function()
    for iX = 1, tGame.Cols do
        for iY = 1, tGame.Rows do
            if tGame.BG[iY] ~= nil and tGame.BG[iY][iX] ~= nil then
                tFloor[iX][iY].iColor =  tonumber(tGame.BG[iY][iX])
                tFloor[iX][iY].iBright = tConfig.Bright 
            end
        end
    end
end

CPaint.PlayerZone = function(iPlayerID, iBright)
    for iX = tGame.StartPositions[iPlayerID].X, tGame.StartPositions[iPlayerID].X+tGame.StartPositionSize-1 do
        for iY = tGame.StartPositions[iPlayerID].Y, tGame.StartPositions[iPlayerID].Y+tGame.StartPositionSize-1 do
            if not tFloor[iX][iY].bDefect then
                tFloor[iX][iY].iColor = tGame.StartPositions[iPlayerID].Color
                tFloor[iX][iY].iBright = iBright
            end
        end
    end
end

CPaint.Crosshair = function()
    if tFloor[CGameMode.iCrosshairX] and tFloor[CGameMode.iCrosshairX][CGameMode.iCrosshairY] then
        tFloor[CGameMode.iCrosshairX][CGameMode.iCrosshairY].iColor = tGame.StartPositions[CGameMode.iPlayerIDToMove].Color
        tFloor[CGameMode.iCrosshairX][CGameMode.iCrosshairY].iBright = tConfig.Bright+2
    end
end

--UTIL прочие утилиты
function CheckPositionClick(tStart, iSizeX, iSizeY)
    for iX = tStart.X, tStart.X + iSizeX - 1 do
        for iY = tStart.Y, tStart.Y + iSizeY - 1 do
            if tFloor[iX] and tFloor[iX][iY] then
                if tFloor[iX][iY].bClick and tFloor[iX][iY].iWeight > 5 then
                    return true
                end 
            end
        end
    end

    return false
end

function SetPositionColorBright(tStart, iSize, iColor, iBright)
    for i = 0, iSize * iSize - 1 do
        local iX = tStart.X + i % iSize
        local iY = tStart.Y + math.floor(i / iSize)

        if not (iX < 1 or iX > tGame.Cols or iY < 1 or iY > tGame.Rows) then     
            tFloor[iX][iY].iColor = iColor
            tFloor[iX][iY].iBright = iBright            
        end
    end
end

function SetRectColorBright(iX, iY, iSizeX, iSizeY, iColor, iBright)
    for i = iX, iX + iSizeX do
        for j = iY, iY + iSizeY do
            if not (i < 1 or i > tGame.Cols or j < 1 or j > tGame.Rows) and not tFloor[i][j].bAnimated then     
                tFloor[i][j].iColor = iColor
                tFloor[i][j].iBright = iBright            
            end            
        end
    end
end

function SetGlobalColorBright(iColor, iBright)
    for iX = 1, tGame.Cols do
        for iY = 1, tGame.Rows do
            tFloor[iX][iY].iColor = iColor
            tFloor[iX][iY].iBright = iBright
        end
    end

    for i, tButton in pairs(tButtons) do
        tButtons[i].iColor = iColor
        tButtons[i].iBright = iBright
    end
end

function SetAllButtonColorBright(iColor, iBright, bCheckDefect)
    for i, tButton in pairs(tButtons) do
        if not bCheckDefect or not tButtons[i].bDefect then
            tButtons[i].iColor = iColor
            tButtons[i].iBright = iBright
        end
    end
end
--//


--//
function GetStats()
    return tGameStats
end

function PauseGame()
    bGamePaused = true
end

function ResumeGame()
    bGamePaused = false
	iPrevTickTime = CTime.unix()
end

function PixelClick(click)
    if tFloor[click.X] and tFloor[click.X][click.Y] then
        if iGameState == GAMESTATE_SETUP and not click.Click then
            AL.NewTimer(500, function()
                tFloor[click.X][click.Y].bClick = false
            end)

            return;
        end

        tFloor[click.X][click.Y].bClick = click.Click
        tFloor[click.X][click.Y].iWeight = click.Weight
    end
end

function DefectPixel(defect)
    if tFloor[defect.X] and tFloor[defect.X][defect.Y] then
        tFloor[defect.X][defect.Y].bDefect = defect.Defect
    end
end

function ButtonClick(click)
    if tButtons[click.Button] == nil then return end
    tButtons[click.Button].bClick = click.Click
end

function DefectButton(defect)
    if tButtons[defect.Button] == nil then return end
    tButtons[defect.Button].bDefect = defect.Defect

    if defect.Defect then
        tButtons[defect.Button].iColor = CColors.NONE
        tButtons[defect.Button].iBright = CColors.BRIGHT0
    end    
end