public with sharing class SDO_EinsteinCopilot_NewReplyCtrl {
    @AuraEnabled(cacheable=true)
    public static List<MapWrapper> getObjectNames() {
        //List<Map<String, String>> objectNames = new List<Map<String, String>>();
        List<MapWrapper> objectNames = new MapWrapper[]{};
        // Get all SObjects dynamically
        List<Schema.SObjectType> objectTypes = new List<Schema.SObjectType>(Schema.getGlobalDescribe().values());
        
        for (Schema.SObjectType objType : objectTypes) {
            Schema.DescribeSObjectResult objDescribe = objType.getDescribe();
            if (objDescribe.isSearchable() && objDescribe.isAccessible() && objDescribe.isQueryable()) {
                objectNames.add(new MapWrapper(objDescribe.getLabel(),objDescribe.getName()));
                /*
                 * Map<String, String> objInfo = new Map<String, String>();
                objInfo.put('value', objDescribe.getName());
                objInfo.put('label', objDescribe.getLabel());
                objectNames.add(objInfo);
*/
            }
        }
        objectNames.sort();
        return objectNames;
    }
    @AuraEnabled(cacheable=true)
    public static List<MapWrapper> getObjectFields(String objectName) {
        List<MapWrapper> fieldInfoList = new MapWrapper[]{};
        
        // Get all fields for the selected object
        Map<String, Schema.SObjectField> fieldsMap = Schema.getGlobalDescribe().get(objectName).getDescribe().fields.getMap();
        for (String fieldName : fieldsMap.keySet()) {
            Schema.DescribeFieldResult fieldDescribe = fieldsMap.get(fieldName).getDescribe();
            
            fieldInfoList.add(new MapWrapper(fieldDescribe.getLabel(),fieldDescribe.getName()));
        }
        
        return fieldInfoList;
    }
    @AuraEnabled(cacheable=true)
    public static List<sObject> executeDynamicSOQL(String objectName, List<String> selectedFields, String searchTerm) {
        // Construct the SELECT clause
        String selectClause = 'SELECT ';
        for(String field : selectedFields) {
            selectClause += field + ', ';
        }
        // Remove trailing comma and space
        selectClause = selectClause.removeEnd(', ');
        
        // Construct the WHERE clause
        String whereClause = ' WHERE Name LIKE \'%' + String.escapeSingleQuotes(searchTerm) + '%\'';
        
        // Construct the SOQL query
        String soqlQuery = selectClause + ' FROM ' + objectName + whereClause;
        
        // Execute the SOQL query
        List<sObject> queryResults = Database.query(soqlQuery);
        
        return queryResults;
    }
    
    public class MapWrapper implements Comparable {
        
        @AuraEnabled public String label {get; set;}
		@AuraEnabled public String value {get; set;}      
        public MapWrapper(String label, String value) {
            this.label = label;
            this.value = value;
        }
        
       public Integer compareTo(Object compareTo) {
            MapWrapper compareToMap = (MapWrapper)compareTo;
            return this.label.compareTo(compareToMap.label);      
        }
    }
}