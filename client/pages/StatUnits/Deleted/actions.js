import rqst from 'helpers/request'
import { actions as rqstActions } from 'helpers/requestStatus'

const stat = (item) => {
    type: STAT,
    item: item
  }
}
