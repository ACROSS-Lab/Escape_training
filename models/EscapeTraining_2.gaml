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
	geometry shape <- square(500#m);
	
	init{
		create evacuation_point with: [location::{0,0}];
		
		create inhabitant number:nb_of_people ;
		
		create hazard;
		
	}
	
	reflex when:empty(inhabitant){
		do pause;
	}
	
}

species hazard {
	
	float speed <- 10#m/#mn; 
	
	init {
		shape <- circle(20#m);
	}
	
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
	
	bool is_hazard <- false;
	evacuation_point safety_point <- evacuation_point closest_to self;
	float perception_dist <- rnd(50.0,500.0);
	
	reflex perceive_hazard when: not is_hazard {
		is_hazard <- not empty (hazard at_distance perception_dist);
	}
	reflex evacuate when:is_hazard {
		do goto target:safety_point;
		if(location = safety_point.location ){
			ask safety_point {do evacue_inhabitant(myself);}
		}
	}
	
	aspect default {
		draw circle(1#m) color:is_hazard ? #red : #blue;
	}
	
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
	output {
		display my_display type:opengl { 
			
			species inhabitant;
			species evacuation_point;
			species hazard transparency:0.7;
			
		}
	}
}
