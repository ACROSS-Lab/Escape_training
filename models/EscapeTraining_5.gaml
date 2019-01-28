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
	float min_perception_distance <- 10.0;
	float max_perception_distance <- 30.0;
	
	string the_alert_strategy;
	float time_before_hazard <- 1#h;
	int nb_stages <- 8;
	
	file road_file <- file("../includes/road_environment.shp");
	file buildings <- file("../includes/building_environment.shp");
	file evac_points <- file("../includes/evacuation_environment.shp");
	file water_body <- file("../includes/sea_environment.shp");
	geometry shape <- envelope(envelope(road_file)+envelope(water_body));
	
	graph<geometry, geometry> road_network;
	map<road,float> road_weights;
	
	int casualties;
	int crowd_casualties;
	
	// TO BE DELETED
	float average_speed <- 0.0 update: mean(inhabitant collect each.real_speed)*3.6;
	float max_density <- 0.0 update: max(road collect (each.users / each.shape.perimeter));
	float av_desntity <- 0.0 update: mean(road where (each.users > 0) collect (each.users / each.shape.perimeter));
	float max_overload <- 0.0 update: max(road collect (each.users / each.capacity));
	float overload <- 0.0 update: mean(road where (each.users > 0) collect (each.users / each.capacity));
	bool agent_speed <- true;
	
	init {
				
		create road from:road_file;
		create building from:buildings;
		create evacuation_point from:evac_points;
		create hazard from: water_body;
		
		create inhabitant number:nb_of_people {
			location <- any_location_in(one_of(building));
			safety_point <- evacuation_point with_min_of (each distance_to self);
		}
		
		create crisis_manager;
		
		road_network <- as_edge_graph(road);
		road_weights <- road as_map (each::each.shape.perimeter);
	
	}
	
	reflex stop_simu when:empty(inhabitant){
		do pause;
	}
	
}

species crisis_manager {
	
	bool alert <- true;
	float alert_range;
	
	int nb_per_stage;
	geometry buffer;
	float distance_buffer;
	
	init {
		// For stage strategy
		int modulo_stage <- length(inhabitant) mod nb_stages = 0 ? 0 : int(length(inhabitant) mod nb_stages / nb_stages) + 1; 
		nb_per_stage <- int(length(inhabitant) / nb_stages) + modulo_stage;
		
		// For spatial strategy
		buffer <- line({0,world.shape.height},{world.shape.width,world.shape.height});
		distance_buffer <- world.shape.height / nb_stages;
		
		alert_range <- (time_before_hazard / 2) / nb_stages;
	}
	
	reflex send_alert when: alert_conditional() {
		ask alert_target() { self.alerted <- true; }
	}
	
	bool alert_conditional {
		switch the_alert_strategy {
			match "STAGE" {
				return (inhabitant first_with (each.alerted = false)) != nil and (cycle = 0 or every(alert_range));
			}
			match "SPATIAL" {
				geometry next_stage <- buffer buffer distance_buffer;
				return every(alert_range) or empty(inhabitant where not(each.alerted) overlapping next_stage);
			}
			default {
				if(alert){
					alert <- false;
					return true;
				} else {
					return false;
				}
			}
		}
	}
	
	list<inhabitant> alert_target {
		switch the_alert_strategy {
			match "STAGE" {
				return nb_per_stage among (inhabitant where (each.alerted = false));
			}
			match "SPATIAL" {
				buffer <- buffer buffer distance_buffer;
				return inhabitant overlapping buffer;
			}
			default {
				return list(inhabitant);
			}
		}
	}
	
}


species hazard {
	
	date catastrophe_date;
	float speed <- 10#m/#mn;
	
	init {
		catastrophe_date <- current_date + time_before_hazard;
	}
	
	reflex expand when:catastrophe_date < current_date {
		shape <- shape buffer (speed * step);
		ask inhabitant overlapping self {
			casualties <- casualties + 1; 
			do die;
		}
		//if(every(refresh_damage)){ 
		ask road where (self covers each) {
			road_network >- self; 
			do die;
		}
		//}
		ask evacuation_point where (each distance_to self < 2#m) {
			list<evacuation_point> available_exit <- evacuation_point where (each != self);
			ask inhabitant where (each.safety_point = self) {
				self.safety_point <- available_exit with_min_of (each distance_to self);
			}
			do die;
		} 
	}
	
	aspect default {
		draw shape color:#blue;
	}
	
}

species inhabitant skills:[moving] {
	
	bool alerted <- false;
	evacuation_point safety_point;
	float speed <- 10#km/#h max:10#km/#h;
	
	/* 
	geometry perception_area; 
	list<inhabitant> user_in_front;
	
	reflex eval_speed when:agent_speed and alerted {
		perception_area <- cone(heading-45.0,heading+45.0) intersection circle(speed * step);
		user_in_front <- (inhabitant overlapping perception_area) - self;
		if(empty(user_in_front)){ 
			speed <- speed + 1;
		} else {speed <- speed / (1+log(length(user_in_front)));}
	}
	* 
	*/
	
	reflex evacuate when:alerted {
		if(agent_speed){do goto target:safety_point on: road_network;}
		else{do goto target:safety_point on: road_network move_weights:road_weights;}
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
	
	action evacue_inhabitant {
		count_exit <- count_exit + 1;
	}
	
	aspect default {
		draw circle(1#m+19#m*count_exit/nb_of_people) color:#green;
	}
	
}

species road {
	
	int users;
	int capacity <- int(shape.perimeter*8);
	float speed_coeff <- 1.0;
	
	reflex update_weights {
		speed_coeff <- exp(-users/capacity);
		road_weights[self] <- shape.perimeter / speed_coeff;
		users <- 0;
	}
	
	aspect default{
		draw shape width: 4#m-(3*speed_coeff)#m color:rgb(55+200*users/capacity,0,0);
	}	
	
}

species building {
	aspect default {
		draw shape color: #gray border: #black;
	}
}

species death {
	aspect default {
		draw rotated_by(rectangle(1,2)+rotated_by(rectangle(1,2), 90.0),45) color:#red border:#black;
	}
}

experiment my_experiment {
	
	parameter "Alert Strategy" var:the_alert_strategy init:"DEFAULT" among:["STAGE","SPATIAL","DEFAULT"];
	parameter "Time before hazard" var:time_before_hazard init:1#h min:5#mn max:2#h;
	parameter "Agent based speed regulation" var:agent_speed init:false;
	
	output {
		display my_display type:opengl { 
			species inhabitant;
			species road;
			species evacuation_point;
			species hazard;
			species building;
			species death;
			
		}
		 
		display chart_display {
			chart "speed_chart" type:series{
				data "average speed" value:average_speed;
			}
		}
		
		monitor number_of_casualties value:casualties;
		
		monitor average_speed value:average_speed;
		monitor max_density value:max_density;
		monitor average_density value:av_desntity;
		monitor overload value:overload;
		monitor max_overload value:max_overload;
		monitor crowd_casualties value:crowd_casualties;
	}
	
}
