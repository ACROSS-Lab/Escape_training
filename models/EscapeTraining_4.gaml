/***
* Name: EscapeTrainingBasic
* Author: kevinchapuis
* Description: 
* Tags: Tag1, Tag2, TagN
***/

model EscapeTrainingBasic

global {
	
	float step <- 10#sec;
	int refresh_damage <- 20#cycles;
	
	int nb_of_people <- 5000;
	float min_perception_distance <- 50.0;
	float max_perception_distance <- 500.0;
	
	file road_file <- file("../includes/road_environment.shp");
	file buildings <- file("../includes/building_environment.shp");
	file evac_points <- file("../includes/evacuation_environment.shp");
	file water_body <- file("../includes/sea_environment.shp");
	geometry shape <- envelope(envelope(road_file)+envelope(water_body));
	
	graph<geometry, geometry> road_network;
	map<road,float> road_weights;
	
	init{
				
		create road from:road_file;
		create building from:buildings;
		create evacuation_point from:evac_points;
		create hazard from: water_body;
		
		create inhabitant number:nb_of_people {
			location <- any_location_in(one_of(building));
			safety_point <- evacuation_point with_min_of (each distance_to self);
		}
		
		road_network <- as_edge_graph(road);
		road_weights <- road as_map (each::each.shape.perimeter);
	}
	
	reflex stop_simu when:empty(inhabitant){
		do pause;
	}
	
}

species hazard {
	
	float speed <- 10#m/#mn;
	
	reflex expand {
		shape <- shape buffer (speed * step);
		ask inhabitant overlapping self { do die; }
		if(every(refresh_damage)){ 
			ask road where (self covers each) {
				road_network >- self; 
				do die;
			}
		}
	}
	
	aspect default {
		draw shape color:#blue;
	}
	
}

species inhabitant skills:[moving] {
	
	bool alerted <- false;
	evacuation_point safety_point;
	float perception_dist <- rnd(min_perception_distance,max_perception_distance);
	
	reflex perceive_hazard when: not alerted {
		alerted <- not empty (hazard at_distance perception_dist);
	}
	
	reflex evacuate when:alerted {
		do goto target:safety_point on: road_network move_weights:road_weights;
		if(current_edge != nil){
			road the_current_road <- road(current_edge);  
			the_current_road.users <- the_current_road.users + 1;
		} 
		
		if(location distance_to safety_point.location < 2#m){ 
			ask safety_point {do evacue_inhabitant;}
			do die;
		}
	}
	
	aspect default {
		draw circle(1#m) color:alerted ? #red : #blue;
	}
	
}

species evacuation_point {
	
	int count_exit <- 0;
	
	reflex disrupt when: not(empty(hazard)) and hazard[0] distance_to self < 1#m {
		list<evacuation_point> available_exit <- evacuation_point where (each != self);
		ask inhabitant where (each.safety_point = self) {
			self.safety_point <- available_exit with_min_of (each distance_to self);
		}
		do die;
	}
	
	action evacue_inhabitant {
		count_exit <- count_exit + 1;
	}
	
	aspect default {
		draw circle(1#m+19#m*count_exit/nb_of_people) color:#green;
	}
	
}

species road {
	
	int users;
	float speed_coeff;
	
	reflex update_weights {
		speed_coeff <- self.shape.perimeter / min(exp(-users/shape.perimeter), 0.1);
		road_weights[self] <- speed_coeff;
		users <- 0;
	}
	
	aspect default{
		draw shape width: 4-(3*speed_coeff)#m color:rgb(55+200*length(users)/shape.perimeter,0,0);
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
