/***
* Name: EscapeTraining1
* Author: kevinchapuis
* Description: Training model of evacuation strategies and catastroph mitigation in urban area
* Tags: ESCAPE, Evacuation strategy, Hazard mitigation
***/

model EscapeTraining1

global {
	
	// PARAMETERS
	float time_before_hazard;
	float hazard_uncertainty;
	
	pair indiv_threshold_gauss;
	int nb_of_people;
	
	bool road_impact <- true;
	
	string the_alert_strategy;
	list<string> the_strategies <- list(string(default_strategy),string(staged_strategy),string(spatial_strategy));
	
	graph<geometry, geometry> road_network;
	map<road,float> road_weights <- [];
	
	file the_sea <- file("../includes/sea_environment.shp");
	file the_ground <- file("../includes/ground_environment.shp");
	geometry shape <- envelope(the_sea+the_ground);
	
	float step <- 2#sec;
	
	/*
	 * OUTPUT SECTION
	 */
	int safe_inhabitant <- 0; // Number of people that reach an evacuation point
	int evacuating_inhabitant <- 0;  // Number of people that want to reach an evacuation point
	
	int casualties <- 0; // Number of people that dies from hazard
	
	float evacuation_time <- 0.0#sec; // Time elapse until the first alert has been sent
	bool evacuation <-false;
	
	/*
	 * USER TRIGGERED DISASTER
	 *
	user_command disaster action: create_disaster;
	action create_disaster {
		point disasterPoint <- #user_location;
		create hazard with: [location::disasterPoint,warning_level::100];
	}
	* 
	*/
	
	init {
		
		create water from:file("../includes/sea_environment.shp");
		create ground from:file("../includes/ground_environment.shp");
		
		create road from:file("../includes/road_environment.shp");
		create building from:file("../includes/building_environment.shp");
		write "Building average height: "+mean(building collect each.height);
		create evacuation_point from:file("../includes/evacuation_environment.shp");
		
		road_network <- as_edge_graph(road);
		road_weights <- road as_map (each::each.shape.perimeter);
		
		create inhabitant number:nb_of_people{
			
			list<building> available_places <- building where not(each.capacity - length(each.occupants) = 0);
			bool in_building <- length(available_places) = 0 ? false : true;  
			if(in_building){
				current_place <- one_of(available_places);
				location <- any_location_in(current_place);
			} else {
				location <- any_location_in(one_of(road));
			} 
			
		}
	
		create hazard with:[water_body::water[0]];
		create crisis_manager with:[evacuation_buffer::rnd(time_before_hazard)];
		
	}
	
	reflex update_indicators {
		safe_inhabitant <- sum(evacuation_point collect each.count_exit);
		evacuating_inhabitant <- inhabitant count each.alerted;
		evacuation_time <- evacuation ? evacuation_time + step : evacuation_time;
	}
	
	reflex stop_simu when:empty(inhabitant) {
		do pause;
	}
	
}

// -------------------- END OF INIT ---------------------- //

/*
 * Main agent to be manipulated: entity that will decide which evacuation strategy to used
 */
species crisis_manager {
	
	float evacuation_buffer;
	float hazard_happen_in <- time_before_hazard update:p_strategy.hazard_schedul();
	
	alert_strategy a_strategy;
	prediction_strategy p_strategy; 
	
	init {
		
		create pessimist_prediction returns:p_strats;
		p_strategy <- p_strats[0];
		
		switch the_alert_strategy {
			match string(default_strategy) {
				create default_strategy returns:strategies; 
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
	
	/*
	 * Send alert when: hazard is confirmed (any intensity exept none) or randomly according to prediction
	 * 
	 * Sended alert is a level from 0 to 1 according to hazard intensity
	 * 
	 */
	reflex send_alert when: evacuation_buffer > hazard_happen_in 
		and a_strategy.alert_conditional() {
			
		// COMPLETLY ARBITRARY
		float hazard_intensity <- log(1+hazard[0].speed);
		
		ask a_strategy.alert_target() { do receive_alert(hazard_intensity); }
		
		world.evacuation <- true;
		write "ALERT SENT AT "+current_date.hour+":"+current_date.minute+":"+current_date.second
			+"\nSTRATEGY: "+string(a_strategy);
	}
	
}

// -------------- //
//   STRATEGIES   //
// -------------- //

species alert_strategy {
	
	bool alert_conditional {
		return true;
	}
	
	list<inhabitant> alert_target {
		return list(inhabitant);
	}
	
}

species default_strategy parent:alert_strategy {
	
	date last_alert;
	
	bool alert_conditional {
		if(last_alert = nil){
			last_alert <- current_date;
			return true;
		} else {
			return false;
		}
	}
	
}

species staged_strategy parent:alert_strategy {
	
	int nb_stage <- 4;
	list<list<inhabitant>> staged_target;
	
	date last_alert;
	float alert_range <- 5#mn;
	
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
		return not(empty(staged_target)) and 
			(last_alert = nil or (current_date - last_alert = alert_range));
	}
	
	list<inhabitant> alert_target {
		container<inhabitant> targets <- staged_target[0];
		staged_target >- targets;
		return targets;
	}
	
}

species spatial_strategy parent:alert_strategy {
	
	geometry d_buffer;
	float distance_buffer <- 100#m;
	int buffered_inhabitants;
	float buffer_tolerance <- 0.1;
	
	int iter <- 1;
	
	bool alert_conditional {
		return length(inhabitant overlapping d_buffer) < (buffered_inhabitants * buffer_tolerance) or iter = 1;
	}
	
	list<inhabitant> alert_target {
		d_buffer <- hazard[0] buffer (distance_buffer * iter);
		list<inhabitant> trgt <- inhabitant overlapping d_buffer;
		buffered_inhabitants <- length(trgt); 
		iter <- iter + 1;
		return trgt;
	}
	
}

species prediction_strategy { float hazard_schedul { return #infinity;} }

species pessimist_prediction parent:prediction_strategy {
	float hazard_schedul { return time_before_hazard * -hazard_uncertainty - cycle * step; }
}

species on_time_prediction parent:prediction_strategy {
	float hazard_schedul { return time_before_hazard - cycle * step; }
}

species uncertainty_prediction parent:prediction_strategy {
	float hazard_schedul {return flip(hazard_uncertainty) ? #infinity : time_before_hazard * (flip(0.5) ? 1 : -1 * hazard_uncertainty) - cycle * step;}
}

// -------------- //
//   INHABITANT   //
// -------------- //

species inhabitant skills:[moving] {
	
	rgb color <- rnd_color(255);
	float tall <- rnd(1.5#m, 1.9#m);
	
	building current_place;
	float speed <- 4#km/#h;
	
	float alert_threshold <- gauss(float(indiv_threshold_gauss.key),float(indiv_threshold_gauss.value));
	bool alerted <- false;
	evacuation_point evac_target;
	
	/*
	 * Evacue goto choosen evacuation point
	 */
	reflex evacuate when:alerted and evacuation_point != nil {
		do goto target:evac_target on:road_network move_weights:road_weights speed:speed;
		write real_speed;
		road the_current_road <- road(current_edge);
		if(the_current_road != nil){
			the_current_road.users <- the_current_road.users + 1;
		}
		if(location = evac_target.location){
			ask evac_target {do evacue_inhabitant(myself);}
		}
	}
	
	/*
	 * perceived alert trigger evacuation point choice if the level if equal or better than alert_threshold
	 * 
	 * People do choose the closest exit
	 *  
	 */
	action receive_alert(float level){
		alerted <- true;
		if(level >= alert_threshold){
			evac_target <- evacuation_point with_min_of (each distance_to self - each distance_to hazard[0]);
		} else {
			alert_threshold <- alert_threshold + alert_threshold / (1-0.95);
		}
	}
	
	action leave_domaged_road {
		location <- any_location_in(road_network.edges closest_to self);
	}
	
	aspect default{
		draw pyramid(tall) color:color;
		draw sphere(0.2#m) at: location + {0,0,tall} color:color;
	}
	
	aspect not_in_building {
		if(current_place = nil){
			draw pyramid(tall) color:color;
			draw sphere(0.2#m) at: location + {0,0,tall} color:color;
		}
	}
	
}

// ------------------ //
//   HAZARD RELATED   //
// ------------------ //

species hazard {
	
	date catastrophe;
	bool triggered <- false;
	
	float speed <- 10#m/#mn;
	water water_body;
	
	init {
		catastrophe <- flip(hazard_uncertainty) ? nil : current_date + time_before_hazard * (flip(0.5) ? 1 : -1 * hazard_uncertainty);
	}
	
	reflex begin when:current_date - catastrophe < step * 2 {
		triggered <- true;
	}
	
	reflex evolve when:triggered {
		geometry expend <- water_body.shape buffer (speed * step);
		water_body.shape <- expend - (expend - world.shape) - building;
		ask inhabitant overlapping water_body {
			casualties <- casualties + 1; 
			do die;
		}
	}
		
	aspect default {
		draw water_body.shape color:#blue depth:1#m;
	}
	
}

species water {}

species evacuation_point {
	
	int count_exit <- 0;
	
	/*
	 * Count and kill people that have been evacuated
	 */
	action evacue_inhabitant(inhabitant people) {
		count_exit <- count_exit + 1;
		ask people {do die;}
	}
	
	aspect default {
		draw circle(10#m) color:#green;
	}
	
}

// ---------------- //
//   ENVIRONEMENT   //
// ---------------- //

species road {

	list<inhabitant> users;
	float capacity;
	float speed_coeff;
	
	int nb_lane <- 2;
	
	reflex disrupt when: road_impact and every(20#cycles) and not(empty(hazard)) {
		loop h over:hazard {
			if(self distance_to h < 1#m){
				road_network >- self;
				ask users { do leave_domaged_road; }
				do die;
			}
		}
	}
	
	reflex update_weights {
		speed_coeff <- exp(-length(users)/capacity);
		road_weights[self] <- speed_coeff;
		users <- [];
	}
	
	aspect default{
		draw shape width: speed_coeff*nb_lane*2.5#m color:rgb(55+200*length(users)/capacity,0,0);
	}	
}

/*
 * USELESS FOR NOW
 */
species building {
	
	float height;
	int capacity;
	
	list<inhabitant> occupants;
	
	aspect default {
		//draw shape depth:length(occupants)/max_capacity*building_height color:#grey;
		draw shape depth:height border:#black color:#white;
	}
	
}

species ground {
	aspect default {
		draw shape color:#grey;
	}
}

experiment my_experiment type:gui {
	parameter "Alert time before catastrophe" var:time_before_hazard init:20#mn;
	parameter "Hazard triggering uncertainty" var:hazard_uncertainty init:0.0;
	parameter "Number of people" var: nb_of_people min: 100 init:5000;
	parameter "Average evacuation individual threshold" var:indiv_threshold_gauss type:pair init:0.0::0.0;
	parameter "Alert Strategy" var:the_alert_strategy init:"Default" among:the_strategies;
	output{
		display my_display type:opengl { 
			//species ground;
			species hazard;
			species building transparency:0.8;
			species road;
			species evacuation_point;
			species inhabitant;
		}
		
		monitor safe_inhabitant value:safe_inhabitant;
		monitor number_of_people_evacuating value:evacuating_inhabitant;
		monitor number_of_casualties value:casualties;
		monitor evacuation_time value:evacuation_time	;
	}
}
