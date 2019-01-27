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
	
	list<string> the_strategies <- list(string(alert_strategy),string(staged_strategy),string(spatial_strategy));
	string the_alert_strategy;
	float time_before_hazard;
	
	file road_file <- file("../includes/road_environment.shp");
	file buildings <- file("../includes/building_environment.shp");
	file evac_points <- file("../includes/evacuation_environment.shp");
	file water_body <- file("../includes/sea_environment.shp");
	geometry shape <- envelope(envelope(road_file)+envelope(water_body));
	
	graph<geometry, geometry> road_network;
	map<road,float> road_weights;
	
	int casualties;
	float average_speed <- 0.0 update: mean(inhabitant collect each.real_speed)*3.6;
	float max_density <- 0.0 update: max(road collect (each.users / each.shape.perimeter));
	float av_desntity <- 0.0 update: mean(road collect (each.users / each.shape.perimeter));
	
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
	
	alert_strategy a_strategy;
	
	init {
		write "Alert strategy to be used: "+(the_alert_strategy=string(alert_strategy)?"default_strategy":the_alert_strategy);
		switch the_alert_strategy {
			match string(alert_strategy) {
				create alert_strategy returns:strategies; 
				a_strategy <- strategies[0];
			}
			match string(staged_strategy) {
				create staged_strategy returns:strategies; 
				a_strategy <- strategies[0];
			}
			match string(spatial_strategy) {
				create spatial_strategy returns:strategies; 
				a_strategy <- strategies[0];
			}
		}	
	}
	
	reflex send_alert when: a_strategy.alert_conditional() {
		ask a_strategy.alert_target() { self.alerted <- true; }
	}
	
}

species alert_strategy {
	
	bool alert <- true;
	
	bool alert_conditional {
		if(alert){
			alert <- false;
			return true;
		} else {
			return false;
		}
	}
	
	list<inhabitant> alert_target {
		return list(inhabitant);
	}
	
}

species staged_strategy parent:alert_strategy {
	
	int nb_stage <- 8;
	list<list<inhabitant>> staged_target;
	
	float alert_range <- (time_before_hazard / 2) / nb_stage;
	
	init {
		list<inhabitant> buffer <- list(inhabitant);
		int nb_per_stage <- int(length(buffer) / nb_stage);
		loop times:nb_stage-1 {
			list<inhabitant> this_stage <- nb_per_stage among buffer;
			buffer >>- this_stage; 
			staged_target <+ this_stage;
		}
		staged_target <+ buffer;
	}
	
	bool alert_conditional {
		return not(empty(staged_target)) and every(alert_range);
	}
	
	list<inhabitant> alert_target {
		container<inhabitant> targets <- staged_target[0];
		staged_target >- targets;
		return targets;
	}
	
}

species spatial_strategy parent:alert_strategy {
	
	geometry d_buffer;
	float distance_buffer <- 50#m;
	int buffered_inhabitants <- [];
	
	float alert_range <- (time_before_hazard / 2) / (world.shape.height / distance_buffer);
	
	bool reverse <- false;
	
	init {
		if(reverse){
			d_buffer <- line({0,world.shape.height},{world.shape.width,world.shape.height});
		} else {
			d_buffer <- line({0,0},{world.shape.width,0});
		}
	}
	
	bool alert_conditional {
		geometry next_stage <- d_buffer buffer distance_buffer;
		return every(alert_range) or empty(inhabitant where not(each.alerted) overlapping next_stage);
	}
	
	list<inhabitant> alert_target {
		d_buffer <- d_buffer buffer distance_buffer;
		list<inhabitant> trgt <- inhabitant overlapping d_buffer;
		buffered_inhabitants <- length(trgt);
		return trgt;
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
	float speed <- 6#km/#h;
	
	reflex evacuate when:alerted {
		if(real_speed > 5#km/#h) {write real_speed * 3.6;}
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
	
	action evacue_inhabitant {
		count_exit <- count_exit + 1;
	}
	
	aspect default {
		draw circle(1#m+19#m*count_exit/nb_of_people) color:#green;
	}
	
}

species road {
	
	int users;
	int capacity <- int(shape.perimeter*6);
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


experiment my_experiment {
	parameter "Alert Strategy" var:the_alert_strategy init:string(alert_strategy) among:the_strategies;
	parameter "Time before hazard" var:time_before_hazard init:1#h min:5#mn max:2#h;
	output {
		display my_display type:opengl { 
			species inhabitant;
			species road;
			species evacuation_point;
			species hazard;
			species building;
		}
		monitor number_of_casualties value:casualties;
		
		monitor average_speed value:average_speed;
		monitor max_density value:max_density;
		monitor average_density value:av_desntity;
	}
	
}
