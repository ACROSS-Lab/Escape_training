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
	
		// PARAMETERS
	float hazard_probability;
	pair indiv_threshold_gauss;
	int nb_of_people;
	
	graph<geometry, geometry> road_network;
	
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
		
		road_network <- as_edge_graph(road);
	
	}
	
}

species inhabitant skills:[moving] {
	
	bool is_hazard;
	evacuation_point safety_point;
	
	reflex evacuate when:is_hazard {
		do goto target:safety_point on:road_network;
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
	
	reflex disrupt when:not(empty(hazard)) {
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
		draw circle(1+count_exit) color:#green;
	}
	
}

experiment my_experiment {
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
