import React from 'react'
import { Button, Form } from 'semantic-ui-react'

import getField from 'components/getField'
import { wrapper } from 'helpers/locale'
import styles from './styles.pcss'

const EditForm = ({ statUnit, errors, localize, onSubmit }) => {
  const fields = statUnit.properties.map(x => getField(x, errors))
  return (
    <div className={styles.edit}>
      <Form className={styles.form} onSubmit={onSubmit} error>
        {fields}
        <br />
        <Button className={styles.sybbtn} type="submit" primary>
          {localize('Submit')}
        </Button>
      </Form>
    </div>
  )
}

const { func } = React.PropTypes

EditForm.propTypes = {
  localize: func.isRequired,
  onSubmit: func.isRequired,
}

export default wrapper(EditForm)
