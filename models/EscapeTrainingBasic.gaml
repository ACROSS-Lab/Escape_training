/***
* Name: EscapeTrainingBasic
* Author: kevinchapuis
* Description: 
* Tags: Tag1, Tag2, TagN
***/

model EscapeTrainingBasic

global {
	
	file road_file <- file("../includes/grid_network.shp");
	file buildings <- file("../includes/buildings.shp");
	file evac_points <- file("../includes/evac_points.shp");
	geometry shape <- envelope(road_file);
	
	graph<geometry, geometry> road_network;
	
	// ---------- //
	// PARAMETERS //
	// ---------- //
	
	// HAZARD
	float hazard_probability;
	bool disrupt_road;
	
	// PEOPLE
	pair indiv_threshold_gauss;
	int nb_of_people;
	
	/*
	 * USER TRIGGERED DISASTER
	 */
	user_command disaster action: create_disaster;
	action create_disaster {
		point disasterPoint <- #user_location;
		create hazard with: [location::disasterPoint];
	}
	
	init{
		
		create road from:road_file;
		create building from:buildings;
		create evacuation_point from:evac_points;
		
		create inhabitant number:nb_of_people with:[location::any_location_in(one_of(building))];
		
		road_network <- as_edge_graph(road);
	
	}
	
	reflex when:empty(inhabitant){
		do pause;
	}
	
}

species inhabitant skills:[moving] {
	
	bool is_hazard <- false update:not(empty(hazard));
	evacuation_point safety_point <- evacuation_point with_min_of (each distance_to self);
	
	reflex evacuate when:is_hazard {
		do goto target:safety_point on:road_network;
		if(self distance_to safety_point < 1#m){
			ask safety_point {do evacue_inhabitant(myself);}
		}
	}
	
	aspect default {
		draw circle(1#m) color:is_hazard ? #red : #blue;
	}
	
}

species hazard {
	
	float size;
	
	init {
		size <- rnd(200#m);
	}
	
	aspect default {
		draw circle(size) at: {location.x,location.y} color:#red;
	}
	
}

species road {
	
	reflex disrupt when: disrupt_road and not(empty(hazard)) {
		loop h over:hazard {
			if(self distance_to h < h.size){
				do die;
			}
		}
	}
	
}

species building {
	
	
}

species evacuation_point {
	
	int count_exit <- 0;
	
	action evacue_inhabitant(inhabitant people) {
		count_exit <- count_exit + 1;
		ask people {do die;}
	}
	
	aspect default {
		draw circle(1#m+9#m*count_exit/nb_of_people) color:#green;
	}
	
}

experiment my_experiment {
	parameter "Number of people" var: nb_of_people min: 100 init:5000;
	parameter "Hazard disrupt road" var:disrupt_road init:false;
	output {
		display my_display type:opengl { 
			species inhabitant;
			species road;
			species evacuation_point;
			species hazard transparency:0.7;
			species building transparency:0.5;
		}
	}
}
