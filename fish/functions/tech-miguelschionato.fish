function tech-miguelschionato --wraps='rsync -avz --delete ~/tech-miguelschionato/html raspberry:/home/miguel/tech-miguelschionato/' --description 'alias tech-miguelschionato rsync -avz --delete ~/tech-miguelschionato/html raspberry:/home/miguel/tech-miguelschionato/'
  rsync -avz --delete ~/tech-miguelschionato/html raspberry:/home/miguel/tech-miguelschionato/ $argv
        
end
