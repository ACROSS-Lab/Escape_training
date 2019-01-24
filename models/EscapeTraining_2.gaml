/***
* Name: EscapeTrainingBasic
* Author: kevinchapuis
* Description: 
* Tags: Tag1, Tag2, TagN
***/

model EscapeTrainingBasic

global {
	
	float step <- 10#sec;
	
	int nb_of_people <- 1000;
	float min_perception_distance <- 50.0;
	float max_perception_distance <- 500.0;
	
	geometry shape <- square(500#m);
	
	init{
		create evacuation_point with: [location::{0,0}];
		
		create inhabitant number:nb_of_people {
			safety_point <- evacuation_point with_min_of (each distance_to self);
		}
		
		create hazard {
			shape <- circle(20#m);
		}
		
	}
	
	reflex stop_simu when:empty(inhabitant){
		do pause;
	}
	
}

species hazard {
	
	float speed <- 10#m/#mn; 
	
	reflex expand {
		shape <- shape buffer (speed * step);
		ask inhabitant overlapping self {
			do die;
		}
	}
	
	aspect default {
		draw shape color:#red;
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
		do goto target:safety_point;
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



experiment my_experiment {
	output {
		display my_display type:opengl { 
			
			species hazard;
			species inhabitant;
			species evacuation_point;
			
		}
	}
}
