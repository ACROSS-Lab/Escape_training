/***
* Name: EscapeTrainingBasic
* Author: kevinchapuis
* Description: 
* Tags: Tag1, Tag2, TagN
***/

model EscapeTrainingBasic

global {
	
	float step <- 10#sec;
	
	int nb_of_people <- 5000;
	float min_perception_distance <- 50.0;
	float max_perception_distance <- 500.0;
	
	file road_file <- file("../includes/road_environment.shp");
	file buildings <- file("../includes/building_environment.shp");
	file evac_points <- file("../includes/evacuation_environment.shp");
	file water_body <- file("../includes/sea_environment.shp");
	geometry shape <- envelope(road_file);
	
	graph<geometry, geometry> road_network;
	
	init{
				
		create road from:road_file;
		create building from:buildings;
		create evacuation_point from:evac_points;
		create hazard from:water_body;
		
		create inhabitant number:nb_of_people {
			safety_point <- evacuation_point with_min_of (each distance_to self);
			location <- any_location_in(one_of(building));
		}
		
		road_network <- as_edge_graph(road);
	}
	
	reflex stop_simu when:empty(inhabitant){
		do pause;
	}
	
}

species hazard {
	
	float speed <- 0.2#km/#h;
	
	reflex expand {
		shape <- shape buffer (speed * step);
		ask inhabitant overlapping self { do die; }
	}
	
	aspect default {
		draw shape color:#blue;
	}
	
}

species inhabitant skills:[moving] {
	
	bool alerted <- false;
	evacuation_point safety_point <- evacuation_point with_min_of (each distance_to self);
	float perception_dist <- rnd(min_perception_distance,max_perception_distance);
	
	reflex perceive_hazard when: not alerted {
		alerted <- not empty (hazard at_distance perception_dist);
	}
	
	reflex evacuate when:alerted {
		do goto target:safety_point on: road_network;
		
		if(location = safety_point.location ){ 
			ask safety_point {do evacue_inhabitant(myself);}
		}
	}
	
	aspect default {
		draw circle(1#m) color:alerted ? #red : #blue;
	}
	
}

species evacuation_point {
	
	int count_exit <- 0;
	
	action evacue_inhabitant(inhabitant people) {
		count_exit <- count_exit + 1;
		ask people {do die;}
	}
	
	aspect default {
		draw circle(1#m+19#m*count_exit/nb_of_people) color:#green;
	}
	
}

species road {
		
	aspect default{
		draw shape color:#black;
	}
	
}

species building {
	aspect default {
		draw shape color: #gray border: #black;
	}
}


experiment my_experiment {
	output {
		display my_display type:opengl { 
			species inhabitant;
			species road;
			species evacuation_point;
			species hazard;
			species building;			
		}
	}
}
