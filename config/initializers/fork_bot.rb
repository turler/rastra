# Logic for forking connections
# The forked process does not have access to static vars as far as I can discern, so I've done some stuff to check if the op threw an exception.
class ProcessManager
  def fork_with_new_connection
    # Store the ActiveRecord connection information
    config = ActiveRecord::Base.remove_connection

    pid = fork do
      # tracking if the op failed for the Process exit
      success = true

      begin
        ActiveRecord::Base.establish_connection(config)
        
        # This is needed to re-initialize the random number generator after forking (if you want diff random numbers generated in the forks)
        srand

        # Run the closure passed to the fork_with_new_connection method
        yield

      rescue Exception => exception
        puts ("Forked operation failed with exception: " + exception)
        
        # the op failed, so note it for the Process exit
        success = false

      ensure
        ActiveRecord::Base.remove_connection
        Process.exit! success
      end
    end

    # Restore the ActiveRecord connection information
    ActiveRecord::Base.establish_connection(config)

    #return the process id
    pid
  end 


  # A static var to keep track of the number of failures
  @@failed = 0
  @@forks = 20

  #forks @@forks processes
  def concurrent_opps iteration
    (1..@@forks).each do |i|
      pid = fork_with_new_connection do
        # simple way to keep track of progress
        puts "Fork: #{i}"

        #necessary to manage activerecord connections since we are forking
        ActiveRecord::Base.connection.reconnect!

        #
        # The whole reason for creating the fork... do some stuff here
        #
        x = rand[25]
        if 0==x then raise Exception "it was 6, and I don't like 6's" end
      end
      
      puts "Process #{pid} completed"
    end
    
    #Wait for all processes to finish before proceeding - collect results as well 
    results = Process.waitall 

    results.each{ |result|
      @@failed += result[1].exitstatus
    }
  end
end