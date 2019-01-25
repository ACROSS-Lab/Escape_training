/***
* Name: EscapeTrainingBasic
* Author: kevinchapuis
* Description: 
* Tags: Tag1, Tag2, TagN
***/

model EscapeTrainingBasic

import "EscapeTraining_5.gaml"

experiment exp type: batch until: empty(inhabitant) repeat: 8 {
	parameter "Alert Strategy" var:the_alert_strategy init:string(default_strategy) among:the_strategies;	
	parameter "Nb people" var: nb_of_people among: [1000,3000,5000,7000,9000,20000];	
	parameter "Time before hazard" var:time_before_hazard init: 1#mn among: [0#mn, 1#mn, 15#mn, 30#mn];

	reflex end_of_runs
	{
		save [int(self),the_alert_strategy,nb_of_people,time_before_hazard,self.seed, simulations mean_of(each.casualties)] type: "csv" to: "result/cas0.01.csv" rewrite: false;
		
//		ask simulations
//		{
//			save [int(self),the_alert_strategy,nb_of_people,time_before_hazard,self.seed,self.casualties] type: "csv" to: "result/cas0.01.csv" rewrite: false;
//		}
	}
	
	permanent {
		display tot { 
			chart "c" type: series {
//				ask simulations {
					data "c"+int(self) value: casualties  ;		
//					data "nb people" value: nb_of_people  ;											
//				}	
			}			
		}
	}
	
}

/*experiment exp2 type: batch until: empty(inhabitant) repeat: 8 {
	parameter "Alert Strategy" var:the_alert_strategy init:string(default_strategy) among:the_strategies;
	parameter "Time before hazard" var:time_before_hazard init:15#mn min:1#mn max:30#mn;
	parameter "Nb people" var: nb_of_people among: [1000,3000,5000,7000,9000]
	
	output {
		display my_display type:opengl { 
			species inhabitant;
			species road;
			species evacuation_point;
			species hazard;
			species building;
			
		}
		monitor number_of_casualties value:casualties;
	}
	
}*/