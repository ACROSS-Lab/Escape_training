/***
* Name: EscapeTrainingEnvironment
* Author: pataillandie and kevinchapuis
* Description: 
* Tags: Tag1, Tag2, TagN
***/

model EscapeTrainingEnvironment

global {
	
	bool water_body <- true;
	
	// Number of road sections
	int nb_xy_intersect <- 10;
	
	// building attributes
	pair floor_range <- 2.4#m::3.4#m;
	int max_floor <- 10;
	
	// Number of exit
	int nb_exit;
	
	// World shape attributes
	int grid_rows const: true <- 100;
	int grid_colums const: true <- 100;	 
	image_file image <- image_file("../includes/DessinLouve2.png");
	geometry shape <- square(500#m);
	
	map<rgb,string> color_to_species <- [rgb (128, 64, 3)::string(ground),#navy::string(water)];
	
	list<road> the_list_of_road;
	
	init {
		
		float t <- machine_time;
		if(water_body){
			write "START CREATION OF THE ENVIRONMENT";
			int image_rows <- matrix(image).rows;
			int image_columns <- matrix(image).columns;
			
			float factorDiscret_width <- image_rows / grid_rows;
			float factorDiscret_height <- image_columns / grid_colums;
			ask cell {		
				color <-rgb( (image) at {grid_x * factorDiscret_height,grid_y * factorDiscret_width}) ;
			} 
			map<rgb, list<cell>> cells_per_color <- cell group_by each.color;
			loop col over: cells_per_color.keys {
				geometry geom <- union(cells_per_color[col]) + 0.001;
				if (geom != nil) {
					string species_name <- color_to_species[col];
					switch species_name {
						match string(water) {
							create water from: geom.geometries;
						}
						match string(ground) {
							create ground from: geom.geometries;
						}
					}
				}
			}
			write "END - TIME ELAPSE: "+((machine_time-t)/1000)+"sec";
		}
		
		write "START CREATION OF ROADS";
		t <- machine_time;
		float x_width <- shape.width / nb_xy_intersect;
		float y_height <- shape.height / nb_xy_intersect;
		float corridors <- (x_width < y_height ? x_width : y_height) / 10;
		list<geometry> lines <- [];
	
		// ROAD SYSTEM
		
		// N/S or S/N roads
		loop x from:1 to:nb_xy_intersect-1 {
			lines <+ flip(0.5) ? 
				line({x*x_width,0}, {x*x_width,world.shape.height}) : 
				line({x*x_width,world.shape.height}, {x*x_width,0});
		}
		// O/E or E/O roads
		loop y from:1 to:nb_xy_intersect-1 {
			lines <+ flip(0.5) ?
				line({0,y*y_height}, {world.shape.width,y*y_height}) :
				line({world.shape.width,y*y_height}, {0,y*y_height});
		}
		
		// Create network of road
		lines <- clean_network(lines,0.0,true,true);
		if(water_body){
			ask water {
				lines >>- lines where (each overlaps self);
			}
		}
		
		loop l over:lines {
			create road {
				shape <- l;
			}
		}	
		
		write "END - "+length(lines)+" ROADS - TIME ELAPSE: "+((machine_time-t)/1000)+"sec";
		
		
		write "START CREATION OF BUILDINGS";
		t <- machine_time;
		loop i_x from:0 to:nb_xy_intersect-1 {
			loop i_y from:0 to:nb_xy_intersect-1 {
				point x_point <- {i_x*x_width+corridors, i_y*y_height+corridors};
				float x_length <- x_width-2*corridors;
				float y_length <- y_height-2*corridors;
				int nb_of_floor <- rnd(1,max_floor);
				create building {
					shape <- polygon(x_point, x_point+{x_length,0}, 
						x_point+{x_length,y_length}, x_point+{0,y_length}); 	
					height <- nb_of_floor * rnd(floor_range.key,floor_range.value)#m;
					capacity <- int(nb_of_floor * shape.area / (10#m^2));
				}
			}
		}
		
		if(water_body){
			ask water {
				ask building overlapping self {
					do die;
				}
			}
		}
		
		write "END - "+length(building)+" BUILDINGS - TIME ELAPSE: "+((machine_time-t)/1000)+"sec";
		
		write "START CREATION OF EVACUATION POINT";
		t <- machine_time;
		list<point> available_exit <- (road accumulate each.shape.points) where (each distance_to world.shape.contour < 2#m);
		loop xt over:nb_exit among available_exit {
			create evacuation_point with:[location::xt];
		} 
		
		write "END - "+length(evacuation_point)+" EVACUATION POINTS - TIME ELAPSE: "+((machine_time-t)/1000)+"sec";
		
		write "EXPORT TO FILES";
		if(water_body){
			save water to:"../includes/sea_environment.shp" type:shp;
			save ground to:"../includes/ground_environment.shp" type:shp;
			save road to:"../includes/road_environment.shp" type:shp;
			save building to:"../includes/building_environment.shp" type:shp;
			save evacuation_point to:"../includes/evacuation_environment.shp" type:shp;
		} else {
			save road to:"../includes/road_grid.shp" type:shp;
			save building to:"../includes/building_grid.shp" with:[height::"height",capacity::"capacity"] type:shp;
			save evacuation_point to:"../includes/evac_points.shp" type:shp;
		}
	}
	
	user_command create_road_from_list {
		create road with: [shape::union(the_list_of_road)];
		ask the_list_of_road { do die; }
		save road to:"../includes/road_environment.shp" type:shp;
	}
	
}

grid cell  width: grid_rows height: grid_colums;

species water {
	aspect default {
		draw shape color: #navy border: #black;
	}
}

species ground {
	aspect default {
		draw shape color: rgb (128, 64, 3) border: #black;
	}
}

species road {
	float capacity;
	aspect default {
		draw shape color:#black;
	}
	
	user_command add_to_list {
		the_list_of_road <+ self;
	}
}

species building {
	float height;
	int capacity;
	aspect default {
		draw shape depth:height border:#black color:#white;
	}
}

species evacuation_point {
	aspect default {
		draw circle(5#m) color:#green;
	}
}

experiment Vectorize type: gui {
	parameter "Number of exit" var:nb_exit init:4;
	parameter "Number of road section" var:nb_xy_intersect init:20;
	output {
		display map_vector type:opengl{
			species water;
			species ground transparency:0.4;
			species building transparency:0.6;
			species road;
			species evacuation_point;
		}
	}
}


