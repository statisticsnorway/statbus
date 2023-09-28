import React, { useState, useCallback, useRef } from 'react'
import { func, shape, arrayOf, number, string } from 'prop-types'
import { Grid, Input, Dropdown, Button, Segment, List } from 'semantic-ui-react'
import Dropzone from 'react-dropzone'

import styles from './styles.pcss'

function Upload({ dataSources, uploadFile, localize }) {
  const [state, setState] = useState({
    description: '',
    dataSourceId: undefined,
    accepted: [],
    isLoading: false,
    dropError: '',
  })

  const dropzoneRef = useRef()

  const handleAcceptedDrop = useCallback((accepted) => {
    const file = accepted[0]
    if (file.name.endsWith('.csv') || file.name.endsWith('.xml') || file.name.endsWith('.txt')) {
      setState(prevState => ({ ...prevState, accepted, dropError: '' }))
    } else {
      setState(prevState => ({
        ...prevState,
        dropError: 'incorrect-format',
        accepted: [],
      }))
    }
  }, [])

  const handleRejectedDrop = useCallback(() => {
    setState(prevState => ({
      ...prevState,
      dropError: 'incorrect-format',
      accepted: [],
    }))
  }, [])

  const handleEdit = prop => (_, { value }) => {
    setState(prevState => ({ ...prevState, [prop]: value }))
  }

  const handleSubmit = () => {
    const file = state.accepted[0]
    const formData = new FormData()
    formData.append('datafile', file, file.name)
    formData.append('DataSourceId', state.dataSourceId)
    formData.append('Description', state.description)

    setState(prevState => ({ ...prevState, isLoading: true }))

    uploadFile(formData, () => {
      setState(prevState => ({
        ...prevState,
        accepted: [],
        isLoading: false,
      }))
    })
  }

  const { dataSourceId, isLoading, description, dropError } = state
  const file = state.accepted[0]
  const canSubmit = file !== undefined && dataSourceId !== undefined
  const options = dataSources.map(x => ({ text: x.name, value: x.id }))

  return (
    <Segment loading={isLoading}>
      <Grid>
        <Grid.Row columns={2}>
          <Grid.Column width={6}>
            <Dropdown
              value={dataSourceId}
              onChange={handleEdit('dataSourceId')}
              options={options}
              placeholder={localize('SelectDataSource')}
              autoComplete="off"
              selection
              fluid
            />
          </Grid.Column>
          <Grid.Column width={10}>
            <Input
              value={description}
              onChange={handleEdit('description')}
              placeholder={localize('EnterDescription')}
              autoComplete="off"
              fluid
            />
          </Grid.Column>
        </Grid.Row>
        <Grid.Row columns={1}>
          <Grid.Column>
            <Dropzone
              ref={dropzoneRef}
              accept=".csv, .xml"
              onDropAccepted={handleAcceptedDrop}
              onDropRejected={handleRejectedDrop}
              className={styles['dz-container']}
              multiple={false}
            >
              {file === undefined ? (
                <p>{localize('DropZoneLabel')}</p>
              ) : (
                <List className={styles[`dz_message_${dropError}`]}>
                  <List.Header content={localize('NextFilesReadyForUpload')} />
                  <List.Item key={file.name} className={styles['dz-list']}>
                    <List.Icon name="file text outline" />
                    <List.Content
                      header={file.name}
                      description={`${file.type} ${Math.ceil(file.size / 1024)}Kb`}
                    />
                  </List.Item>
                </List>
              )}
              {dropError && (
                <p className={styles[`dz_message_${dropError}`]}>
                  {localize('IncorrectFileFormat')}
                </p>
              )}
              <p className={styles[`dz_message_${dropError}`]}>
                {`${localize('OnlySupportedFormatsAllowed')}: CSV, XML`}
              </p>
            </Dropzone>
          </Grid.Column>
        </Grid.Row>
        <Grid.Row>
          <Grid.Column>
            <Button
              onClick={canSubmit ? handleSubmit : () => dropzoneRef.current.open()}
              content={localize(canSubmit ? 'UpLoad' : 'SelectFile')}
              icon="upload"
              color={canSubmit ? 'green' : 'blue'}
              disabled={!!dropError}
            />
          </Grid.Column>
        </Grid.Row>
      </Grid>
    </Segment>
  )
}

Upload.propTypes = {
  dataSources: arrayOf(shape({
    id: number.isRequired,
    name: string.isRequired,
  })),
  uploadFile: func.isRequired,
  localize: func.isRequired,
}

Upload.defaultProps = {
  dataSources: [],
}

export default Upload
