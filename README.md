# bocm
BlueOcean control manager.

Automatyczne, konfigurowalne budowanie systemu na podstawie wskazanego obrazu.
Obrazy pobierane przy pomocy rclone, współpracuje więc z większością popularnych chmur.

####################################################################################################
# UWAGA dotyczaca pliku partitions.yml!
#
# Partycje są montowane w kolejności występowania w pliku, nie w kolejności numeracji
# Mozna wpisać do pliku w kolejności nie rosnącej numeracji, czyli np partycja 2 moe być przed 1
#
# Przyklad: Jeśli pratycja 1 ma być montowana wewnątrz partycji 2 to 
#          partycja 2 musi występować w pliku przez partycją 1
####################################################################################################