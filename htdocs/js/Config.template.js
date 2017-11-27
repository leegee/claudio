{
    "apiKey": "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX",
    "clientId": "XXXXXXXXXXXXXXXXXXXXXXXXXXX.apps.googleusercontent.com",
    "discoveryUrls": ["https://www.googleapis.com/discovery/v1/apis/drive/v3/rest"],
    "scopes": [
        "https://www.googleapis.com/auth/fusiontables",
        "https://www.googleapis.com/auth/drive",
        "https://www.googleapis.com/auth/plus.login"
    ],
    "fusion": {
        "name": "lee-dev",
        "countiesTableId": "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX",
        "sheetNameStem": "lee-dev-",
        "maxRetries": 3
    },
    "endpoints": {
        "uploadDb": "/cgi-bin/upload-skus.cgi",
        "previewDb": "/cgi-bin/upload-skus.cgi?action=previewDb",
        "lookupSkus": "/cgi-bin/lookup.cgi",
        "status": "/cgi-bin/upload-skus.cgi?action=status"
    },
    "indexBaseDir": "/temp/"
}