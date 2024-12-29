package tesis.unir;

import javax.ejb.Stateless;

@Stateless
public class HelloBean {
    public String sayHello() {
        return "Hello from EJB!";
    }
}
