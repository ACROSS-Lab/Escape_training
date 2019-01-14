/***
* Name: EscapeTrainingBasic
* Author: kevinchapuis
* Description: 
* Tags: Tag1, Tag2, TagN
***/

model EscapeTrainingBasic

global {
	
	float step <- 10#sec;
	
	geometry shape <- square(500#m);
	
	init{
		create hazard;
	}
}

species hazard {
	
	float speed <- 10#m/#mn;
	
	init {
		shape <- circle(20#m);
	}
	
	reflex expand {
		shape <- shape buffer (speed * step);
	}
	
	aspect default {
		draw shape color:#red;
	}
	
}

experiment my_experiment {
	output {
		display my_display type:opengl { 
			species hazard transparency:0.7;
		}
	}
}
