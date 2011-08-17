/**
@author Pat Patterson - ppatterson@salesforce.com

Force.com Toolkit for SimpleGeo

An Apex interface to the SimpleGeo API

Example usage:

// Create a client ready to use
SimpleGeo client = new SimpleGeo();

// Get context for an address - this includes latitude, longitude, 
// postal code, state etc
SimpleGeo.Context context = 
	client.getContextFromAddress('1 Market St, San Francisco, CA');

// Get context for a point (latitude, longitude)
SimpleGeo.Context context = client.getContext(37.793755, -122.395584);

// Get context for the caller's IP address
SimpleGeo.Context context = client.getContextFromIPAddress();

// Get context for an IP address
SimpleGeo.Context context = client.getContextFromIPAddress('8.8.8.8');

// Print out some information from the context
System.debug(LoggingLevel.ERROR,'lat '+context.query.latitude+
	', lon '+context.query.longitude+', address '+context.query.address);

// These are SimpleGeo handles
String california = 'SG_2MySaPILVQG3MoXrsVehyR_37.215297_-119.663837';
String attpark = 'SG_4H2GqJDZrc0ZAjKGR8qM4D_37.778406_-122.389506';
String belltower = 
	'SG_5JkVsYK82eLj26eomFrI7S_37.795027_-122.421583@1291796505';

// Get details on a feature (identified by its handle)
SimpleGeo.Feature feature = client.getFeature(attpark);

// Print the name of the feature
System.debug(LoggingLevel.ERROR, feature.properties.get('name').getString());

// Get all the Starbucks within 0.5km of a point
SimpleGeo.Feature[] features = client.getPlaces(37.793755, -122.395584, 
	new Map<String, String>{'radius' => '0.5', 'q' => 'Starbucks'});

// Get all the Starbucks within 0.5km of an address
SimpleGeo.Feature[] features = 
	client.getPlacesNearAddress('1 Market St, San Francisco, CA', 
	new Map<String, String>{'radius' => '0.5', 'q' => 'Starbucks'});

// Get all the Starbucks within 10km of an IP address
SimpleGeo.Feature[] features = client.getPlacesNearIPAddress('8.8.8.8', 
	new Map<String, String>{'radius' => '10', 'q' => 'Starbucks'});

// Print the addresses of a list of features
for ( SimpleGeo.Feature feature: features ) {
    System.debug(LoggingLevel.ERROR, 
			feature.properties.get('address').getString());
}

// Put a record in a layer
SimpleGeo.Feature feature = new SimpleGeo.Feature();
feature.geometry = new SimpleGeo.Point(latitude, longitude);
feature.properties = new Map<String, SimpleGeo.PropertyValue>();
feature.properties.put('name', new SimpleGeo.PropertyValue(name));
client.putRecord('my.layer.name', id, feature);

// Get records close to a given point
List<Record> records = getNearby('my.layer.name', latitude, longitude, radius);

// Low level 'raw' API access - useful for returning JSON to JavaScript in a 
// Visualforce page
String url = '/0.1/records/my.layer.name/nearby/'+
    latitude+','+longitude+'.json?radius='+radius;
String json = client.sendRequestRaw(url, null, null);

 */
public with sharing class SimpleGeo {
    private String api;
    private String simpleGeoService;
    
    public SimpleGeo() {
        api = 'http://api.simplegeo.com';
        simpleGeoService = 'SimpleGeo';
    }

    public SimpleGeo(String simpleGeoService) {
        api = 'http://api.simplegeo.com';
        this.simpleGeoService = simpleGeoService;
    }

    public SimpleGeo(String simpleGeoService, String api) {
        this.api = api;
        this.simpleGeoService = simpleGeoService;
    }
    
    public class SimpleGeoException extends Exception {}
    
    public virtual class Geometry {
    	public String typ;
    }
    
    public virtual class Position {
        public Double x;
        public Double y;
        public Double z;
        public Position() {        	
        }
        public Position(Double lat, Double lon) {
            this.x = lon;
            this.y = lat;
        }        
    }
    
    public virtual class Point extends Geometry {
    	public Point() {
    		typ = 'Point';
    	}
        public Point(Double lat, Double lon) {
            typ = 'Point';
            coordinates = new Position(lat, lon);
        }
        public Point(Decimal lat, Decimal lon) {
            typ = 'Point';
            coordinates = new Position((Double)lat, (Double)lon);
        }
        public Position coordinates; 
    } 
    
    public virtual class LineString extends Geometry {
        public LineString() {
            typ = 'LineString';
        }
        public Position[] coordinates; 
    }
    
    public virtual class Polygon extends Geometry {
        public Polygon() {
            typ = 'Polygon';
        }
        public LineString[] coordinates;
    }
    
    public virtual class PropertyValue {
        public Object obj;
        public List<Object> lst;
        
        public PropertyValue(Object obj) {
            this.obj = obj;
        }
        public PropertyValue(List<Object> lst) {
            this.lst = lst;
        }
        
        // I don't seem to be able to define my own toString :-(
        public String getString() {
            if ( obj != null ) {
                return String.valueOf(obj);
            }
            
            if ( lst != null ) {
                String str = '[';
                for ( Object item: lst ) {
                    str += String.valueOf(item);
                }
                str += ']';
                return str;
            }
            
            return 'null';
        }
    }
    
    public virtual class Record {
        public String typ;
        public String id;
    }
    
    public virtual class Feature extends Record {
    	public Feature() {
    		typ = 'Feature';
    	}
        public Geometry geometry;
        public String id;
        public Map<String, PropertyValue> properties;
    }
    
    public virtual class Query {
        public Double latitude;
        public Double longitude;
    }
    
    public virtual class Classifier {
        public String category;
        public String typ;
        public String subcategory;
    }
    
    public virtual class FeatureRef {
        public String handle;
        public String name;
        public String license;
        public Double[] bounds;
        public String abbr;
        public Classifier[] classifiers;
    }
    
    public virtual class Demographics {
        public Integer metro_score;
    }

    public virtual class Context {
        public Query query;
        public Double timestamp;
        public FeatureRef[] features;
        // Weather
        public Demographics demographics;
        // Intersections
        public Feature address;
    }
    
    public virtual class Layer {
    	public String name;
        public String title;
        public String description;
        public Boolean publik;
        // created and updated should be Long, but Apex JSONObject doesn't support it yet
        public Double created;
        public Double updated;
    }
    
    public class LayersResult {
        public Layer[] layers;
        public String nextCursor;
        
        public LayersResult(Layer[] layers, String nextCursor) {
        	this.layers = layers;
        	this.nextCursor = nextCursor;
        }
    }
    
    private class JsonPosition extends Position {
        public JsonPosition(list<JSONObject.value> valueList) {
            x = valueList[0].dnum;
            y = valueList[1].dnum;
            if (valueList.size() > 2) {
                z = valueList[2].dnum;
            }
        }
    }
    
    private class JsonLineString extends LineString {
        public JsonLineString(list<JSONObject.value> valueList) {
            Integer size = valueList.size();
            coordinates = new JsonPosition[size];
            for (Integer i = 0; i < size; i++) {
                coordinates[i] = new JsonPosition(valueList[i].values);
            }
        }
    }
    
    private class JsonPoint extends Point {
        public JsonPoint(JSONObject jsonObj) {
            coordinates = new JsonPosition(jsonObj.getValue('coordinates').values);
        }
    }
    
    private class JsonPolygon extends Polygon {
        public JsonPolygon(JSONObject jsonObj) {
            Integer size = jsonObj.getValue('coordinates').values.size();
            coordinates = new JsonLineString[size];
            for (Integer i = 0; i < size; i++) {
                coordinates[i] = new JsonLineString(jsonObj.getValue('coordinates').values[i].values);
            }
        }
    }
    
    private static Geometry makeGeometry(JSONObject jsonObj) {
        String str = jsonObj.getValue('type').str;
        if (str.equalsIgnoreCase('Point')) {
            return new JsonPoint(jsonObj);
        } else if (str.equalsIgnoreCase('Polygon')) {
            return new JsonPolygon(jsonObj);
        } else {
            throw new SimpleGeoException('Unsupported geometry type: '+str);
        }
    }
    
    private static Map<String, PropertyValue> makeProperties(JSONObject jsonObj) {
        Map<String, PropertyValue> properties = new Map<String, PropertyValue>();
        
        for ( String key: jsonObj.keys() ) {
            if (key.equals('classifiers')) {
                Integer size = jsonObj.getValue(key).values.size();
                Classifier[] classifiers = new Classifier[size];
                for (Integer i = 0; i < size; i++) {
                    classifiers[i] =  new JsonClassifier(jsonObj.getValue(key).values[i].obj);
                }
                properties.put(key, new PropertyValue(classifiers));
            } else if (key.equals('tags')){
                Integer size = jsonObj.getValue(key).values.size();
                String[] tags = new String[size];
                for (Integer i = 0; i < size; i++) {
                    tags[i] = jsonObj.getValue(key).values[i].str;
                }
                properties.put(key, new PropertyValue(tags));
            } else {
                properties.put(key, new PropertyValue(jsonObj.getValue(key).str));
            }
        }
        
        return properties;
    }
    
    private class JsonFeature extends Feature {
        public JsonFeature(JSONObject jsonObj) {
            geometry = makeGeometry(jsonObj.getValue('geometry').obj);
            typ = jsonObj.getValue('type').str;
            id = (jsonObj.getValue('id') != null )
                    ? jsonObj.getValue('id').str : null;
            properties = makeProperties(jsonObj.getValue('properties').obj);
        }
    }
    
    private static Feature[] makeFeatureList(JSONObject jsonObj) {
        Integer size = ( jsonObj.getValue('features') != null ) 
                ? jsonObj.getValue('features').values.size()
                : 0;
        Feature[] features = new Feature[size];
        for (Integer i = 0; i < size; i++) {
            features[i] =  new JsonFeature(jsonObj.getValue('features').values[i].obj);
        }
        return features;
    }
    
    private static Layer[] makeLayerList(JSONObject jsonObj) {
        Integer size = ( jsonObj.getValue('layers') != null ) 
                ? jsonObj.getValue('layers').values.size()
                : 0;
        Layer[] layers = new Layer[size];
        for (Integer i = 0; i < size; i++) {
            layers[i] =  new JsonLayer(jsonObj.getValue('layers').values[i].obj);
        }
        return layers;
    }
    
    private class JsonQuery extends Query {
        public JsonQuery(JSONObject jsonObj) {
            latitude = jsonObj.getValue('latitude').dnum;
            longitude = jsonObj.getValue('longitude').dnum;
        }
    }
    
    private class JsonClassifier extends Classifier {
        public JsonClassifier(JSONObject jsonObj) {
            category = jsonObj.getValue('category').str;
            typ = (jsonObj.getValue('type') != null) 
                    ? jsonObj.getValue('type').str : null;
            subcategory = (jsonObj.getValue('subcategory') != null) 
                    ? jsonObj.getValue('subcategory').str : null;
        }
    }
    
    public class JsonContext extends Context {
        public JsonContext(JSONObject jsonObj) {
            if (jsonObj.getValue('code') != null) {
                throw new SimpleGeoException('SimpleGeo error '
                        +jsonObj.getValue('code').num+' '
                        +jsonObj.getValue('message').str); 
            }
            query = new JsonQuery(jsonObj.getValue('query').obj);
            timestamp = jsonObj.getValue('timestamp').dnum;
            Integer size = jsonObj.getValue('features').values.size();
            features = new FeatureRef[size];
            for (Integer i = 0; i < size; i++) {
                features[i] =  new JsonFeatureRef(jsonObj.getValue('features').values[i].obj);
            }
            demographics = (jsonObj.getValue('demographics') != null) 
                ? new JsonDemographics(jsonObj.getValue('demographics').obj) : null;
            address = (jsonObj.getValue('address') != null )
                    ? new JsonFeature(jsonObj.getValue('address').obj) : null;
        }
    }
    
    private class JsonFeatureRef extends FeatureRef {       
        public JsonFeatureRef(JSONObject jsonObj) {
            handle = jsonObj.getValue('handle').str;
            name = jsonObj.getValue('name').str;
            license = jsonObj.getValue('license').str;
            
            Integer size = jsonObj.getValue('bounds').values.size();
            bounds = new Double[size];
            for (Integer i = 0; i < size; i++) {
                bounds[i] =  jsonObj.getValue('bounds').values[i].dnum;
            }
            
            abbr = jsonObj.getValue('abbr').str;
            
            size = jsonObj.getValue('classifiers').values.size();
            classifiers = new Classifier[size];
            for (Integer i = 0; i < size; i++) {
                classifiers[i] =  new JsonClassifier(jsonObj.getValue('classifiers').values[i].obj);
            }
        }
    }
    
    private class JsonDemographics extends Demographics {
        public JsonDemographics(JSONObject jsonObj) {
            if (jsonObj.getValue('metro_score') != null) {
                metro_score = jsonObj.getValue('metro_score').num;
            }
        }
    }
    
    private class JsonLayer extends Layer {
        public JsonLayer(JSONObject jsonObj) {
            if (jsonObj.getValue('name') != null) {
                name = jsonObj.getValue('name').str;
            }
            if (jsonObj.getValue('title') != null) {
                title = jsonObj.getValue('title').str;
            }
            if (jsonObj.getValue('name') != null) {
                name = jsonObj.getValue('name').str;
            }
            if (jsonObj.getValue('publik') != null) {
                publik = jsonObj.getValue('publik').bool;
            }
            if (jsonObj.getValue('created') != null) {
                created = jsonObj.getValue('created').dnum;
            }
            if (jsonObj.getValue('updated') != null) {
                updated = jsonObj.getValue('updated').dnum;
            }
        }
    }
    
    private static Record makeRecord(JSONObject jsonObj) {
    	Record record;
    	
        String typ = jsonObj.getValue('type').str;
        if (typ == 'feature') {
            record = new JsonFeature(jsonObj);
            if(jsonObj.getValue('id') != null) {
            	record.id = jsonObj.getValue('id').str;
            }                
        } else {
        	throw new SimpleGeoException('Unsupported record type: '+typ);
        }
        
    	return record;
    }
    
    public String sendRequestRaw(String url, String method, String body) {
        HttpRequest req = new HttpRequest();
        req.setMethod((method != null) ? method : 'GET');
        req.setEndpoint(api+url);
        if (body != null) {
            System.debug('Sending body '+body);
            req.setBody(body);
        }
        
        OAuth oa = new OAuth();
        if(!oa.setService(simpleGeoService)) {
            System.debug(oa.message);
            return null;
        }
        oa.sign(req);
        
        System.debug('Sending request...');        
        Http h = new Http();
        HttpResponse res = h.send(req);
        System.debug('Received response ('+res.getStatusCode()+' '+res.getStatus()+')');
        
        String rbody = res.getBody().replace('\n', '');
        
        System.debug('Received body '+rbody);
        
        return rbody;
    }
    
    private JSONObject sendRequest(String url, String method, String body) {
        return new JSONObject(sendRequestRaw(url, method, body));
    }
    
    private JSONObject sendRequest(String url) {
    	return sendRequest(url, null, null);
    }
    
    public Feature getFeature(String handle) {
        System.debug('getFeature('+handle+')');

        String url = '/1.0/features/'+handle+'.json';

        return new JsonFeature(sendRequest(url));
    }
    
    public Context getContext(Double latitude, Double longitude) {
        System.debug('getContext('+latitude+', '+longitude+')');

        String url = '/1.0/context/'+latitude+','+longitude+'.json';

        return new JsonContext(sendRequest(url));
    }

    public Context getContext(Decimal latitude, Decimal longitude) {
        return getContext(latitude.doubleValue(), longitude.doubleValue());
    }

    // Accept address in as a string - e.g. '1 Market St, San Francisco, CA'
    public Context getContextFromAddress(String address) {
        System.debug('getContextFromAddress('+address+')');

        String url = '/1.0/context/address.json?address="'+EncodingUtil.urlEncode(address,'UTF-8')+'"';

        return new JsonContext(sendRequest(url));
    }
    
    public Context getContextFromIPAddress(String ip) {
        System.debug('getContextFromIPAddress('+ip+')');

        String url = '/1.0/context/'+ip+'.json';

        return new JsonContext(sendRequest(url));
    }
    
    public Context getContextFromIPAddress() {
        return getContextFromIPAddress('ip');
    }
    
    public Feature[] getPlaces(Double latitude, Double longitude, Map<String,String> arguments) {
        System.debug('getPlaces('+latitude+', '+longitude+','+arguments+')');
        
        String url = '/1.0/places/'+latitude+','+longitude+'.json';

        Boolean first = true;        
        if ( arguments != null ) {
            for ( String key: arguments.keySet() ) {
                url += ( first ) ? '?' : '&';
                first = false;
                url += key + '=' + arguments.get(key);
            }
        }

        return makeFeatureList(sendRequest(url));
    }
    
    public Feature[] getPlaces(Double latitude, Double longitude) {
        return getPlaces(latitude, longitude, null);
    }
    
    public Feature[] getPlaces(Decimal latitude, Decimal longitude, Map<String,String> arguments) {
        return getPlaces(latitude.doubleValue(), longitude.doubleValue(), arguments);
    }
    
    public Feature[] getPlaces(Decimal latitude, Decimal longitude) {
        return getPlaces(latitude.doubleValue(), longitude.doubleValue(), null);
    }
    
    public Feature[] getPlacesNearAddress(String address, Map<String,String> arguments) {
        System.debug('getPlacesNearAddress('+address+','+arguments+')');
        
        String url = '/1.0/places/address.json?address="'+EncodingUtil.urlEncode(address,'UTF-8')+'"';

        if ( arguments != null ) {
            for ( String key: arguments.keySet() ) {
                url += '&' + key + '=' + arguments.get(key);
            }
        }

        return makeFeatureList(sendRequest(url));       
    }
    
    public Feature[] getPlacesNearAddress(String address) {
        return getPlacesNearAddress(address, null);
    }
    
    public Feature[] getPlacesNearIPAddress(String ip, Map<String,String> arguments) {
        System.debug('getPlacesNearIPAddress('+ip+','+arguments+')');
        
        String url = '/1.0/places/'+ip+'.json';

        Boolean first = true;        
        if ( arguments != null ) {
            for ( String key: arguments.keySet() ) {
                url += ( first ) ? '?' : '&';
                first = false;
                url += key + '=' + arguments.get(key);
            }
        }

        return makeFeatureList(sendRequest(url));       
    }
    
    public Feature[] getPlacesNearIPAddress(Map<String,String> arguments) {
        return getPlacesNearIPAddress('ip', arguments);
    }
    
    public Feature[] getPlacesNearIPAddress(String ip) {
        return getPlacesNearIPAddress(ip, null);
    }
    
    public Feature[] getPlacesNearIPAddress() {
        return getPlacesNearIPAddress('ip', null);
    }
    
    public LayersResult getLayers(Integer lim, String cursor) {
        System.debug('getLayers('+lim+','+cursor+')');
        
        String url = '/0.1/layers.json';
        String sep = '?';
        if ( lim > 0 ) {
        	url += '?limit='+lim;
        	sep = '&';
        }
        if ( cursor != null ) {
            url += sep+'cursor='+cursor;
        }
        
        JSONObject obj = sendRequest(url);
        
        LayersResult result = new LayersResult(makeLayerList(obj), 
            (obj.getValue('next_cursor') != null) ? obj.getValue('next_cursor').str : null);

        return result;           	
    }
    
    public LayersResult getlayers(Integer lim) {
    	return getLayers(lim, null);
    }

    public LayersResult getlayers() {
    	return getLayers(0, null);
    }
    
    public void putLayer(Layer layer) {
    	System.debug('putLayers('+layer.toString()+')');
        
        String url = '/0.1/layers/'+layer.name+'.json';
        
        JSONObject obj = new JSONObject();
        if ( layer.title != null ) {
            obj.putOpt('title', new JSONObject.value(layer.title));
        }
        if ( layer.description != null ) {
            obj.putOpt('description', new JSONObject.value(layer.description));
        }
        if ( layer.publik != null ) {
	        obj.putOpt('public', new JSONObject.value(layer.publik));
        }        
        if ( layer.created != null ) {
            obj.putOpt('created', new JSONObject.value(layer.created));
        }
        if ( layer.updated != null ) {
            obj.putOpt('updated', new JSONObject.value(layer.updated));
        }
    	
    	sendRequest(url, 'PUT', obj.valueToString());
    }
    
    public Record getRecord(String layer, String id) {
        System.debug('getRecord('+id+')');

        String url = '/0.1/records/'+layer+'/'+id+'.json';

        return makeRecord(sendRequest(url));
    }
    
    JSONObject putGeometry(Geometry geometry) {
        JSONObject obj = new JSONObject();
        
        if ( geometry.typ != null ) {
            obj.putOpt('type', new JSONObject.value(geometry.typ));
        }
        List<JSONObject.Value> coordinates = new List<JSONObject.Value>();
        if (geometry.typ.equalsIgnoreCase('Point')) {
        	Point p = (Point)geometry;
        	coordinates.add(new JSONObject.Value(p.coordinates.x));
            coordinates.add(new JSONObject.Value(p.coordinates.y));
        } else if (geometry.typ.equalsIgnoreCase('Polygon')) {
            Polygon p = (Polygon)geometry;
            for (Integer i = 0; i < p.coordinates.size(); i++) {
            	List<JSONObject.Value> lineStrings = new List<JSONObject.Value>();
            	for (Integer j = 0; j < p.coordinates[i].coordinates.size(); j++) {
            		List<JSONObject.Value> points = new List<JSONObject.Value>();
	                points.add(new JSONObject.Value(p.coordinates[i].coordinates[j].x));
	                points.add(new JSONObject.Value(p.coordinates[i].coordinates[j].y));
                    lineStrings.add(new JSONObject.Value(points));
            	}
            	coordinates.add(new JSONObject.Value(lineStrings));
            }
        } else {
            throw new SimpleGeoException('Unsupported geometry type: '+geometry.typ);
        }
        obj.putOpt('coordinates', new JSONObject.Value(coordinates));
        
        return obj;
    }
    
    JSONObject putProperties(Map<String, PropertyValue> properties) {
        JSONObject obj = new JSONObject();
        
        for (String key: properties.keySet()) {
        	obj.putOpt(key, new JSONObject.Value(properties.get(key).getString()));
        }

        return obj;
    }
    
    public void putRecord(String layer, String id, Record record) {
        System.debug('putRecord('+layer+', '+id+', '+record.toString()+')');
        
        String url = '/0.1/records/'+layer+'/'+id+'.json';
        
        JSONObject obj = new JSONObject();
        obj.putOpt('type', new JSONObject.value(record.typ));
        if ( record.typ == 'Feature' ) {
        	Feature feature = (Feature)record;
	        if ( feature.geometry != null ) {
	            obj.putOpt('geometry', new JSONObject.Value(putGeometry(feature.geometry)));
	        }
	        if ( feature.properties != null ) {
	            obj.putOpt('properties', new JSONObject.Value(putProperties(feature.properties)));
	        }
        } else {
        	throw new SimpleGeoException('Unsupported record type: '+record.typ);
        }
        
        sendRequest(url, 'PUT', obj.valueToString());
    }
    
    public Record[] getNearby(String layer, Decimal lat, Decimal lon, Decimal radius) {
    	System.debug('getNearby('+layer+', '+lat+', '+lon+')');
    	
    	String url = '/0.1/records/'+layer+'/nearby/'+lat+','+lon+'.json';
    	
    	if ( radius > 0 ) {
    		url += '?radius='+radius;
    	}
    	
    	return makeFeatureList(sendRequest(url));
    }
    
    public Record[] getNearby(String layer, Decimal lat, Decimal lon) {
        return getNearby( layer, lat, lon, -1);
    }
}