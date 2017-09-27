GOOGLE ACCOUNT INFO

	http://www.google.com/a/izelplants.com
	maps@izelplants.com
	pw: Maperz1220

CREATING THE SPREADSHEET

With PuTTY, Terminal, iTerm or simillar, SSH to the relevant computer.

Chnage to the root directory of the mappign folder — this is not in the web site root.

Then run the following command to learn about what that command does, and what files it 
uses, type the following at the same command line prompt:

	perldoc scripts/create_fusion.pl

NB You may need to press 'Q' when you are finished reading that document.

CREATING THE APP

The clientId and apiKey are created via API pages:
	
	https://code.google.com/apis/console

	http://code.google.com/p/google-api-javascript-client/wiki/Authentication

The US counties geographical data, originally from the US Census Bureau:

	https://support.google.com/fusiontables/answer/1182141?hl=en

This is the table to merge with the output of `scripts/create_fusion.pl`:

	https://www.google.com/fusiontables/DataSource?docid=0IMZAFCwR-t7jZnVzaW9udGFibGVzOjIxMDIxNw#map:id=17

Google Drive (formerly Google Docs) is where the spreadsheet is imported to create a Fusion Table:

	https://drive.google.com

Instructions for merging the geographical table and the spreadshet:

	https://support.google.com/fusiontables/answer/171254?hl=en

GOOGLE DEVELOPER CONSOLE

ME:
	Izel_Distribution
	LOCALHOST API KEY: AIzaSyCBeQP3Cje-GNZTxD0enheKc3lEu4CGzuY
	LEEGODDARD.nET API KEY: AIzaSyA9xkZrMWurQT8GcggBSYdgBAEUunGFG7o

IZEL:
	http://www.google.com/a/izelplants.com
	maps@izelplants.com
	pw: Maperz1220

	https://code.google.com/apis/console/b/1/?noredirect&pli=1

	Key for browser apps (with referers)
	API key: 	
	AIzaSyDBob2s-CgtHT6172BXX8PzEinSG3qyp3g
	Referers: 	
	Any referer allowed
	Activated on: 	May 14, 2014 11:20 AM
	Activated by: 	maps@izelplants.com – you 

	OAuth:
	Callback: https://code.google.com/apis/console/b/1/?noredirect&pli=1
	Client_id: 75996919250.apps.googleusercontent.com
	Client_Secret: c0Zl_OLQPyJvKMA7ZrqWAdSG
	
	

	API ACCESS CONTROL
	https://code.google.com/apis/console/b/1/?noredirect&pli=1#project:75996919250:access
	Edit to limit referers to izelplants.com

SETUP GOOGLE DOCS / GOOGLE DRIVE

Go to Google Docs. Sign in to your Google Account or create a Google Account if you don't already have one. (Note that you while can use a Google Apps for your Domain account for Fusion Tables, you will not be able to create maps.)

Click the "Create" button.

Click the "Connect more apps" bar at the bottom of the resulting list.
Type "fusion tables" in the "Search Apps" box and hit the "Enter" key.

Click the blue "+ CONNECT" button, then click the "OK" button in the confirmation dialog box.

Click "Create > Fusion Table (experimental)".

In the Import new table dialog box, click "Choose File".

Select the .csv file output by the script, and click "Next".

Check that the data is formatted correctly and click "Next".

Give your table the name 'IzelSku' (as set in the JS as MERGED_TABLE) and click "Finish".





Merged table:
https://www.google.com/fusiontables/data?docid=1IvEqDnZROHNXXU4dQIyQG-a8JuLEPtPqFsd4a97c#rows:id=1
