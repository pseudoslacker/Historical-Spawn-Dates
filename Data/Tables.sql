/*
	Historical Spawn Dates
	by Gedemon (2017)
	
*/

-----------------------------------------------
-- Create Tables
-----------------------------------------------

CREATE TABLE IF NOT EXISTS HistoricalSpawnDates
	 (	Civilization TEXT NOT NULL UNIQUE,
		StartYear INTEGER DEFAULT -10000);
		
CREATE TABLE IF NOT EXISTS HistoricalSpawnDates_NewWorld
	 (	Civilization TEXT NOT NULL UNIQUE,
		StartYear INTEGER DEFAULT -10000);
		
CREATE TABLE IF NOT EXISTS IsolatedCivs
	 (	Civilization TEXT NOT NULL UNIQUE);
	 
CREATE TABLE IF NOT EXISTS EraBuildingCivs
	 (	Civilization TEXT NOT NULL UNIQUE);